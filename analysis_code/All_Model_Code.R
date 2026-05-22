
library(tidyverse)
library(broom)
library(MuMIn)
library(dplyr)
library(ggplot2)
library(scales)
library(ggeffects)

########################################  Data Prep ######################################## 
dat_csv <- read_csv("") # add csv location here
dat_master <- dat_csv %>%
  mutate(
    LC_Name = case_when(
      LC_Name %in% c("Grasslands","Open Shrublands","Savannas","Woody Savannas","Closed Shrublands","Permanent Wetlands") ~ "Open Forest", 
      LC_Name %in% c("Evergreen Needleleaf Forests","Evergreen Broadleaf Forests",
                     "Deciduous Needleleaf Forests","Deciduous Broadleaf Forests","Mixed Forests") ~ "Closed Forest",
      TRUE ~ as.character(LC_Name)
    ),
    LC_Name = factor(LC_Name)
  ) %>%
  filter(LC_Name %in% c("Open Forest","Closed Forest")) #%>%

#mutate(LC_Name = factor(LC_Name))



######################## Model Function ###############################

forest_model_function <- function(dat, forest_type) { 
  
  # Variable Prep
  ft_name <- gsub(" ", "", forest_type)
  string_ModelName <- paste0(ft_name, "Fit")

  
  out_dir_base <- "" # base of output directory here
  
  out_dir <- file.path(out_dir_base, ft_name)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE) # creates directory if not there
  
  
  # set Joint Model
  dat_ft <- if (forest_type == "Joint Model") {
    dat # open and closed forest become Joint Model
  } else {
    filter(dat, LC_Name ==forest_type)
  }
  
  ###### Run the Weather Windows#####
  # Temp, Precip and RH
  #rm(out, aic_temp, aic_precip, aic_rh, k) 
  seq1 <- seq(-15, 0, 1)
  seq2 <- seq(1, 15, 1)
  
  out <- vector("list", length(seq1) * length(seq2))
  aic_temp <- c()
  aic_precip <- c()
  aic_rh <- c() 
  
  k <- 0
  
  for (i in seq1) {
    
    for (j in seq2) {
      
      k <- k + 1
      
      modeldat_tmp <- dat_ft %>%
        filter(
          offset >= i & offset < i + j
        ) %>%
        group_by(
          FireID,
          LIWType,
          fire_type,
          FireSize
        ) %>%
        summarize(
          t2m_mean = mean(t2m_mean),
          rh_mean = mean(rh_mean),
          tp_mean = sum(tp_mean),
          .groups ="drop_last"
        ) #%>%
      
      fit_temp_tmp <- glm(
        fire_type ~ t2m_mean, 
        data = modeldat_tmp,
        family = binomial("logit")
      )
      
      fit_precip_tmp <- glm(
        fire_type ~ tp_mean, 
        data = modeldat_tmp,
        family = binomial("logit")
      )
      fit_rh_tmp <- glm(
        fire_type ~ rh_mean, 
        data = modeldat_tmp,
        family = binomial("logit")
      )   
      
      out[[k]] <- list(
        broom::tidy(fit_temp_tmp),
        broom::tidy(fit_precip_tmp),
        broom::tidy(fit_rh_tmp)
      ) %>%
        bind_rows()
      
      aic_temp <- c(aic_temp, AIC(fit_temp_tmp))
      aic_precip <- c(aic_precip, AIC(fit_precip_tmp))
      aic_rh <- c(aic_rh, AIC(fit_rh_tmp))
    }
    
  }
  
  coefs <- out %>%
    set_names(
      paste(
        rep(seq1, each = length(seq2)),
        rep(seq2, time = length(seq1)),
        sep = "."
      )
    ) %>%
    bind_rows(.id = "lag") %>%
    separate(
      "lag",
      c("lag", "length"),
      "\\."
    ) %>%
    filter(
      term != "(Intercept)"
    ) %>%
    mutate(
      lag = as.integer(lag),
      length = as.integer(length),
      aic = c(rbind(aic_temp, aic_precip, aic_rh))
    )
  # print(aic_temp)
  write.csv(coefs,
            file.path(out_dir, paste0(string_ModelName,"_coefs_leadlag.csv")),
            row.names = TRUE)
  ########################################  Pretty Plots - Lag & Window ######################################## 
  
  
  term_labels <- c(
    "t2m_mean" = "Temperature",
    "tp_mean" = "Precipitation",
    "rh_mean" = "Relative Humidity"
  )
  
  coefs <- coefs %>%
    mutate(term = factor(term, levels = names(term_labels)))
  
  
  p_aic <- ggplot(coefs) +
    geom_tile(aes(x = lag, y = length, fill = aic)) +
    scale_fill_viridis_c(name = "AIC") +
    facet_wrap(~ term, labeller = labeller(term = term_labels)) +
    geom_point(
      data = coefs %>%
        filter(term != "(Intercept)") %>%
        group_by(term) %>%
        summarize(
          lag = lag[which.min(aic)],
          length = length[which.min(aic)],
          .groups = "drop"
        ),
      aes(x = lag, y = length),
      col = "white",
      size = 2
    ) +
    labs(x = "Lag (days)", y = "Window length (days)") +
    theme_bw()
  
  p_aic
  
  ggsave(file.path(out_dir, paste0(string_ModelName,"_aic_lag_window.png")),
         p_aic, width = 8, height = 5, dpi = 300)
  
  ggplot(
    data = coefs
  ) +
    geom_tile(
      aes(
        x = lag,
        y = length,
        fill = aic
      )
    ) +
    scale_fill_viridis_c() +
    facet_wrap(
      ~term
    ) +
    geom_point(
      data = coefs %>% 
        filter(term != "(Intercept)") %>%
        group_by(
          term
        ) %>%
        summarize(
          lag = lag[which.min((aic))],
          length = length[which.min((aic))]
        ),
      aes(
        x = lag,
        y = length
      ),
      col = "white"
    )
  
  lags <- coefs %>% 
    filter(term != "(Intercept)") %>%
    group_by(
      term
    ) %>%
    summarize(
      lag = lag[which.min(aic)],
      length = length[which.min(aic)]
    ) %>%
    mutate(
      lag_end = lag + length
    )
  
  print(string_ModelName)
  print(lags)
  
  write.csv(lags,
            file.path(out_dir, paste0(string_ModelName,"_lags.csv")),
            row.names = TRUE)
  
  
  ######################################## Model Prep ################################################################################################################################################################
  
  # set each set of fire data to be one singular fire
  modeldat_final <- dat_ft %>%
    group_by(
      FireID,
      fire_type,
      LC_Name,
      multiplicity_mean,
      peakcurrent_mean,
      polarity_mean,
      duration_mean,
      NPP
    ) %>%
    # build predictor variables
    summarize(
      dry_lightning = sum(tp_mean[offset == 0]) < 2.54, # creates dry lighting 
      t2m_mean = mean(t2m_mean[offset >= lags[lags$term == "t2m_mean", "lag"][[1]] & offset < lags[lags$term == "t2m_mean", "lag_end"][[1]]]), # set temp within its weather window
      tp_mean = sum(tp_mean[offset >= lags[lags$term == "tp_mean", "lag"][[1]] & offset < lags[lags$term == "tp_mean", "lag_end"][[1]]]), # set precip within its weather window
      rh_mean = mean(rh_mean[offset >= lags[lags$term == "rh_mean", "lag"][[1]] & offset < lags[lags$term == "rh_mean", "lag_end"][[1]]]),   # set RH within its weather window
      ws_mean = ws_mean[offset == 0], # set wind to day 0
      peakcurrent_mean = mean(abs(peakcurrent_mean)), # take absolute value of peak current
      .groups = "drop"
    ) %>%
    mutate(forest_type = forest_type)
  
  modeldat_final_nona <- modeldat_final %>%
    #convert categorical variables to factors
    mutate(
      LC_Name       = factor(LC_Name),
      polarity_mean = factor(polarity_mean)
    ) %>%
    #remove rows with missing values
    drop_na(duration_mean, peakcurrent_mean, fire_type, t2m_mean, tp_mean, multiplicity_mean, dry_lightning, NPP,LC_Name, polarity_mean, ws_mean, rh_mean) %>%  
    # ztransform to standardize predictors (better comparability)
    mutate( 
      tp_mean_ztrans = as.double(scale(tp_mean)),
      t2m_mean_ztrans = as.double(scale(t2m_mean)),
      ws_mean_ztrans = as.double(scale(ws_mean)),
      rh_mean_ztrans = as.double(scale(rh_mean)),
      multiplicity_mean_ztrans = as.double(scale(multiplicity_mean)),
      peakcurrent_mean_ztrans = as.double(scale(peakcurrent_mean)),
      duration_mean_ztrans = as.double(scale(duration_mean)),
      NPP_ztrans = as.double(scale(NPP))
    ) 
  
  #print(names(modeldat_final_nona))
  
  # Count the number of offset == 0 values for Open Forest and Closed Forest used in the final model
  offset0_counts <- modeldat_final_nona %>%
    group_by(LC_Name) %>%
    summarize(
      n_offset0 = n()
    )
  
  print("Number of offset == 0 values used in the final model:")
  print(offset0_counts)
  
  
  # Add standard deviation and mean
  std_mean_stats <-  modeldat_final_nona %>%
    summarize(
      across(
        c(
          duration_mean, peakcurrent_mean, t2m_mean, tp_mean, multiplicity_mean, NPP, ws_mean, rh_mean 
        ),
        list(mean=mean, sd=sd),
        .names = "{.col}_{.fn}"
      )
    ) %>%
    pivot_longer(
      everything(),
      names_to = c("term", ".value"),
      names_pattern = "^(.*)_(mean|sd)$"
    ) %>%
    
    mutate(term = case_when(
      term == "NPP" ~ "NPP_ztrans",
      TRUE ~ paste0(term, "_ztrans")
    ))
  
  #head(modeldat_final_nona)
  
  
  ######################################## Model###################################################################
  
  
  # set LC_Name to matter only in the Joint Model so it can distinguish between the two forest types
  stopifnot("tp_mean_ztrans" %in% names(modeldat_final_nona))
  print(dim(modeldat_final_nona))
  if (forest_type == "Joint Model") {
    ModelFit <- glm(
      fire_type ~  LC_Name + tp_mean_ztrans * t2m_mean_ztrans +
        duration_mean_ztrans + peakcurrent_mean_ztrans +
        multiplicity_mean_ztrans + polarity_mean + dry_lightning +
        NPP_ztrans + ws_mean_ztrans + rh_mean_ztrans,
      data = modeldat_final_nona,
      family = binomial(link = "logit"),
      na.action = na.fail  )
  } else {
    ModelFit <- glm(
      fire_type ~ tp_mean_ztrans * t2m_mean_ztrans +
        duration_mean_ztrans + peakcurrent_mean_ztrans +
        multiplicity_mean_ztrans + polarity_mean + dry_lightning +
        NPP_ztrans + ws_mean_ztrans + rh_mean_ztrans,
      data = modeldat_final_nona,
      family = binomial(link = "logit"),
      na.action = na.fail 
      
    )
    
  }
  
  print(ModelFit)
  fit_summary <- summary(ModelFit)
  coef_table  <- as.data.frame(fit_summary$coefficients)
  write.csv(coef_table,
            file.path(out_dir, paste0(string_ModelName,"_coefficients.csv")),
            row.names = TRUE)
  
  
  ################################# Model CSVs ###########################################
  
  #rank model by AIC
  aic_models <- MuMIn::dredge(ModelFit, trace = 0, rank = "AICc")
  
  # Save & export every model
  all_models_csv <- file.path(out_dir, paste0(string_ModelName, "_all_models.csv"))
  write.csv(as.data.frame(aic_models), all_models_csv, row.names = FALSE)
  
  # select just htose less than 2 from best AIC
  aic_models_delta2 <- subset(aic_models, delta <= 2)
  if (nrow(aic_models_delta2) == 0) aic_models_delta2 <- aic_models[1, , drop = FALSE]
  
  # Refit 
  mods_delta2 <- get.models(aic_models, subset = delta <= 2)
  if (length(mods_delta2) == 0) mods_delta2 <- list(get.models(aic_models, 1)[[1]])  
  
  if (length(mods_delta2) >1){
    
    avg_fit <- model.avg(mods_delta2)
    
    # get coefficients 
    coef_full <- as.data.frame(summary(avg_fit)$coefmat.full)
    coef_full$term <- rownames(coef_full)
    rownames(coef_full) <- NULL
    coef_full
    
    # Get the 95% CI for the averaged model
    ci_full <- as.data.frame(confint(avg_fit, full = TRUE))
    ci_full$term <- rownames(ci_full)
    rownames(ci_full) <- NULL
    names(ci_full)[1:2] <- c("conf.low_logit", "conf.high_logit")
    
    imp_vec <- MuMIn::sw(aic_models_delta2)}
  
  else { 
    
    
    # in case only 1 model
    avg_fit <- mods_delta2[[1]]
    sm <- summary(avg_fit)
    sm 
    coef_full <- as.data.frame(sm$coefficients)
    coef_full$term <-rownames(coef_full)
    rownames(coef_full) <- NULL
    
    ci_full <- as.data.frame(confint(avg_fit))
    ci_full$term <- rownames(ci_full)
    rownames(ci_full) <- NULL
    names(ci_full)[1:2] <- c("conf.low_logit", "conf.high_logit")
    
    imp_vec <- setNames(rep(1, nrow(coef_full)), coef_full$term) }
  
  imp_df  <- data.frame(term = names(imp_vec),
                        rel_importance = as.numeric(imp_vec),
                        row.names = NULL)
  
  #rename columns
  coef_full <- coef_full %>%
    rename(
      SE = "Std. Error",
      z_value = "z value",
      p_value = "Pr(>|z|)")
  
  # ORs
  res <- coef_full %>%
    left_join(ci_full, by = "term") %>%
    left_join(imp_df, by = "term") %>%
    transmute(
      term,
      estimate_logit = Estimate,
      se_logit = SE, 
      conf.low_logit,
      conf.high_logit,
      z_value = z_value,
      p_value = p_value,
      or_estimate  = exp(estimate_logit),
      or_conf.low  = exp(conf.low_logit),
      or_conf.high = exp(conf.high_logit),
      rel_importance
    ) 
  
  # add standard deviation and mean that we computed above
  
  res <- res %>%
    left_join(std_mean_stats, by = "term")
  
  # export AIC & avg coefficients
  model_table <- as.data.frame(aic_models_delta2)
  
  model_table$model_rank <- seq_len(nrow(model_table))
  
  
  avg_csv <- file.path(out_dir,paste0(string_ModelName, "_model_avg_coefficients.csv"))
  set_csv <- file.path(out_dir, paste0(string_ModelName, "_model_set_delta2.csv"))
  
  write.csv(res, avg_csv, row.names = FALSE)
  write.csv(model_table, set_csv, row.names = FALSE) 
  
  #return values
  return(list(
    forest_type = forest_type,
    fit = ModelFit
  ))
  
}



######################## Run Models / For Loop ###############################
forest_types <- c("Open Forest", "Closed Forest","Joint Model")

results <- list()

for (fts in forest_types) {results[[fts]] <- forest_model_function(dat_master, forest_type = fts)}

OpenForestFit   <- results[["Open Forest"]]$fit
ClosedForestFit <- results[["Closed Forest"]]$fit
JointModelFit   <- results[["Joint Model"]]$fit




######################## PlotxTemp Model Image ###############################

model_fits <- list(
  "Open Forest"   = OpenForestFit,
  "Closed Forest" = ClosedForestFit,
  "Joint Model"   = JointModelFit
)


temp_precip_input <- function(mod, name, lc_name = "Open Forest") {
  
  preddat <- expand.grid(
    tp_mean_ztrans = c(-2, 0, 2),
    t2m_mean_ztrans = seq(-2, 2, length.out = 100),
    ws_mean_ztrans = 0,
    rh_mean_ztrans = 0,
    dry_lightning = FALSE,
    duration_mean_ztrans = 0,
    peakcurrent_mean_ztrans = 0,
    multiplicity_mean_ztrans = 0,
    polarity_mean = levels(mod$model$polarity_mean)[1],
    NPP_ztrans = 0
  )
  
  preddat$polarity_mean <- factor(
    preddat$polarity_mean,
    levels = levels(mod$model$polarity_mean)
  )
  
  if ("LC_Name" %in% names(mod$model)) {
    preddat$LC_Name <- factor(lc_name, levels = levels(mod$model$LC_Name))
  }
  
  pred <- predict(mod, newdata = preddat, type = "link", se.fit = TRUE)
  
  preddat$pred  <- plogis(pred$fit)
  preddat$lower <- plogis(pred$fit - 1.96 * pred$se.fit)
  preddat$upper <- plogis(pred$fit + 1.96 * pred$se.fit)
  preddat$model <- name
  
  preddat
}

all_models <- list()

for (fts in names(model_fits)) {all_models[[fts]] <- temp_precip_input(mod = model_fits[[fts]],name = fts)}

all_models_df <- bind_rows(all_models)

all_models_df$model <- factor(
  all_models_df$model,
  levels = c("Joint Model", "Closed Forest", "Open Forest")
)

all_models_df$tp_mean_ztrans <- factor(
  all_models_df$tp_mean_ztrans,
  levels = c(-2, 0, 2)
)

precip_colors <- c("-2" = "#3B1F70", "0" = "#1C8C8C", "2" = "#7AD63A")

tempprecip_plot <- ggplot(
  all_models_df,
  aes(
    x = t2m_mean_ztrans,
    y = pred,
    color = factor(tp_mean_ztrans),
    fill = factor(tp_mean_ztrans)
  )
) +
  geom_ribbon(
    aes(ymin = lower, ymax = upper),
    alpha = 0.25,
    color = NA
  ) +
  geom_line(linewidth = 1) +
  facet_wrap(~model, nrow = 1) +
  scale_color_manual(
    values = precip_colors,
    labels = c("-2" = "-2 SD", "0" = "Mean", "2" = "+2 SD")
  ) +
  scale_fill_manual(
    values = precip_colors,
    labels = c("-2" = "-2 SD", "0" = "Mean", "2" = "+2 SD")
  ) +
  labs(
    x = "Temperature (z)",
    y = "Ignition Probability",
    color = "Precipitation",
    fill = "Precipitation"
  ) +
  theme_bw() +
  theme(
    panel.grid.major = element_line(color = "grey85", linewidth = 0.3),
    panel.grid.minor = element_blank(),
    text = element_text(family = "Arial", size = 11),
    strip.text = element_text(family = "Arial", size = 11),
    legend.text = element_text(family = "Arial", size = 11),
    legend.title = element_text(family = "Arial", size = 11),
    axis.title = element_text(family = "Arial", size = 11),
    strip.background = element_rect(fill = "grey95"),
    panel.spacing = unit(0.2, "lines"),
    legend.position = "right",
    legend.box = "vertical",
    legend.spacing.y = unit(0.5, "pt"),
    panel.spacing.x = unit(1, "lines"),
    aspect.ratio = 1
  )

tempprecip_plot

out_dir <- "" #  out directory here
ggsave(file.path(out_dir, paste0("tempprecip_plot.png")),
       tempprecip_plot, width = 7.5, height = 3, dpi = 300)
