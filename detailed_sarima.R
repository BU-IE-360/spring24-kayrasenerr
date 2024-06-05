# Loading the required libraries
require(forecast)
require(data.table)
require(lubridate)

# Assessing data path
data_path <- 'C:/Users/kayra/Desktop/Okul/3-2/ie360_project/'
file_production <- paste0(data_path, 'production_by_hours.csv')

# Reading the production data and format the date
production_data <- fread(file_production)
production_data$date <- as.Date(production_data$date, format = "%d.%m.%y")

# Checking if the table is updated correctly
tail(production_data$date)

# Defining the hours
hourly_columns <- names(production_data)[9:24]

# Forecasting with SARIMA models with different seasonality values and detailed diagnostics
forecast_with_detailed_arima <- function(data, forecast_ahead, target_name, seasonal_freqs = c(7, 30, 365)) {
  command_string <- sprintf('input_series=data$%s', target_name)
  eval(parse(text = command_string))
  
  # Checking for actual missing values in the input series
  if (any(is.na(input_series))) {
    stop(sprintf("The input series %s contains missing values.", target_name))
  }
  
  # Standardizing the input series: this became required because the model started to gave
  # forecast in orders of 100 for H8 a few times, so we decided to normalize and de-normalize 
  # the forecasts, which solved the issue.
  mean_val <- mean(input_series, na.rm = TRUE)
  sd_val <- sd(input_series, na.rm = TRUE)
  standardized_series <- scale(input_series) 
  
  # Initializing performance measures
  best_aic <- Inf
  best_model <- NULL
  
  # Checking for weekly, monthly, and yearly seasonality periods and pick the best model
  for (freq in seasonal_freqs) {
    ts_input_series <- ts(standardized_series, frequency = freq)
    
    # Trying to fit a SARIMA model, catch potential errors
    fitted <- tryCatch(auto.arima(ts_input_series, seasonal = TRUE), error = function(e) NULL)
    
    if (!is.null(fitted) && fitted$aic < best_aic) {
      best_aic <- fitted$aic
      best_model <- fitted
    }
  }
  
  # Notifying if there are any problems
  if (is.null(best_model)) {
    stop(sprintf("Failed to fit a model for %s", target_name))
  }
  
  # Checking the residuals of the selected model
  checkresiduals(best_model)
  
  # Forecasting
  forecasted <- tryCatch(forecast(best_model, h = forecast_ahead), error = function(e) NULL)
  
  # Notifying if there are any problems
  if (is.null(forecasted)) {
    stop(sprintf("Failed to forecast for %s", target_name))
  }
  
  # Converting forecast back to original scale
  forecasted_original <- (forecasted$mean * sd_val) + mean_val
  
  return(list(forecast = as.numeric(forecasted_original), model = best_model))
}

# Defining the forecast period
forecast_ahead <- 1

# Initializing a list to store forecasts for each hourly column
results <- vector('list', length(hourly_columns))

# Iterating over each hourly column
for (h in hourly_columns) {
  cat(sprintf("Processing %s...\n", h))  # Debugging output
  # Making the forecast for the current hourly column
  forecast_result <- tryCatch(forecast_with_detailed_arima(production_data, forecast_ahead, h, seasonal_freqs = c(7, 30, 365)),
                              error = function(e) {
                                cat(sprintf("Error processing %s: %s\n", h, e$message))
                                return(NULL)
                              })
  
  if (!is.null(forecast_result)) {
    # Storing the forecast result in the list
    results[[h]] <- forecast_result$forecast
  } else {
    results[[h]] <- NA  # Handling failed forecasts
  }
}


# Transforming results to character and apply value limits
hourly_forecasts_numeric <- as.numeric(unlist(results))
hourly_forecasts_numeric

# Negative values are impossible and >10 values are exceptional, so we fixed them
hourly_forecasts_numeric[hourly_forecasts_numeric < 0] <- 0
max(hourly_forecasts_numeric)
hourly_forecasts_numeric[hourly_forecasts_numeric > 10] <- 10

# Adding the first 4 and last 4 hours predictions and copying them to clipboard
hourly_forecasts_numeric <- c(rep(0, 4), hourly_forecasts_numeric, rep(0, 4))
hourly_forecasts_character <- as.character(hourly_forecasts_numeric)
writeClipboard(hourly_forecasts_character)
