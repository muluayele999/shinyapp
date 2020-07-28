# Analyses ----
# ** Meta-Analysis ----
# **** Selection of between-study variance estimator
# Only shown if re-model was selected (default)
output$select_re_type <- renderUI({
  req(input$metamodel)
  if(input$metamodel == "re"){
    selectInput(inputId = "select_re_type",
                label = "Select Estimator of Between-Study Variance",
                choices = c("DerSimonian-Laird (DL)", "Hedges (HE)",
                            "Hunter-Schmidt (HS)", "Sidik-Jonkman (SJ)",
                            "Maximum-Likelihood (ML)", "Restricted Maximum-Likelihood (REML)",
                            "Empirical Bayes Estimator (EB)", "Paule-Mandel Estimator (PM)"),
                selected = "Restricted Maximum-Likelihood (REML)")
  }
})

# store estimator
estim <- reactive({
  
  validate(
    need(isTruthy(input$select_re_type), "")
  )
  
  if (input$metamodel == "re"){
    estim <- switch(input$select_re_type,
                    "DerSimonian-Laird (DL)" = "DL", 
                    "Hedges (HE)" = "HE",
                    "Hunter-Schmidt (HS)" = "HS",
                    "Sidik-Jonkman (SJ)" = "SJ",
                    "Maximum-Likelihood (ML)" = "ML",
                    "Restricted Maximum-Likelihood (REML)" = "REML",
                    "Empirical Bayes Estimator (EB)" = "EB", 
                    "Paule-Mandel Estimator (PM)" = "PM")
  } else if (input$metamodel == "fe"){
    estim<- "FE"
  }
  estim
})

# **** Run the meta-analysis ----
meta_res_output <- reactive({
  # req(input$metamodel)
  validate(
    need(isTruthy(data_reac$DT[[para$es]]) & isTruthy(data_reac$DT[[para$se]]), 
         "Please select columns for effect size and standard error"))
  validate(
    need(isTruthy(estim()), 
         "Please select estimation method"))
  
  
  
  res <- rma(yi = data_reac$DT[[para$es]], sei = data_reac$DT[[para$se]],
             method = estim())
  
  
})  

# **** Prep output ----

output$meta_res <- renderPrint({
  summary(meta_res_output())
})

output$meta_out_1 <- renderText(
  sprintf("%s Model; k = %s%s", 
          if(input$metamodel == "fe") {paste("Fixed-Effect")} else {paste("Random-Effects")},
          meta_res_output()$k.all,
          if(input$metamodel == "fe"){paste("")} else {sprintf("; tau^2 estimator: %s", meta_res_output()$method)})
)


output$meta_out_2 <- renderText(
  sprintf("%s = %.2f, se = %.2f, 95%% CI [%.2f; %.2f], p %s, z = %.2f", 
          para$es,
          meta_res_output()$b,
          meta_res_output()$se,
          meta_res_output()$ci.lb,
          meta_res_output()$ci.ub,
          if(meta_res_output()$pval < .0001){paste("< .0001")} else {paste("= ", round(meta_res_output()$pval, 4))},
          meta_res_output()$zval)
)

output$meta_out_3 <- renderTable(
  data.frame(txt = c("tau^2 (estimated amount of total heterogeneity):",
                     "tau (square root of estimated tau^2 value):",
                     "I^2 (total heterogeneity / total variability):",
                     "H^2 (total variability / sampling variability):"),
             val = c(paste(round(meta_res_output()$tau2, 4), " (SE = ", round(meta_res_output()$se.tau2, 4), ")", sep = ""),
                     round(sqrt(meta_res_output()$tau2), 4),
                     paste(round(meta_res_output()$I2, 2), "%", sep = ""),
                     round(meta_res_output()$H2, 2))), colnames = FALSE
)

output$meta_out_4 <- renderText(
  sprintf("Q(df = %.0f) = %.4f, p %s", meta_res_output()$k.all - 1, meta_res_output()$QE, 
          if(meta_res_output()$QEp < 0.0001){paste("< .0001")} else {paste("= ", format(round(meta_res_output()$QEp, 4), 
                                                                                        scientific = FALSE))})
  
  
)


output$dwn_meta_res <- downloadHandler(
  filename = "meta_results.txt",
  content = function(file) {
    sink(file)
    print(meta_res_output())
    sink()
  }
)

output$dwn_meta_res_obj <- downloadHandler(
  filename = "meta_results.RDS",
  content = function(file){
    saveRDS(meta_res_output(), file = file)
  }
)

# **** Sensitivity Analysis Plot ----

res.estim <- reactive({
  validate(
    need(isTruthy(data_reac$DT[[para$es]]) & isTruthy(data_reac$DT[[para$se]]), 
         "Please select columns for effect size and standard error"))
  
  
  # calculate all models
  estim <- c("FE", "DL", "HE", "HS", "SJ", "ML", "REML", "EB", "PM")
  
  res.sens.est <- lapply(estim, function(x){
    res <- rma(yi = data_reac$DT[[para$es]], sei = data_reac$DT[[para$se]],
               method = x)
    data.frame(es = res$b, se = res$se)
  })
  
  # name list according to method
  names(res.sens.est) <- estim
  
  # create dataframe for plotting
  df.sens <- as.data.table(rbindlist(res.sens.est, idcol = "method"))
  df.sens[, `:=` (method_ordered = fct_reorder(method, es),
                  label = paste(round(es, 2), " (", round(es - 1.96 * se, 2),
                                "; ", round(es + 1.96 * se, 2), ")", sep = ""))]
  df.sens
})

# create forest plot
output$meta_sens <- renderPlot({
  req(res.estim())
  req(estim())
  ggplot(data = res.estim()) + 
    
    # add vertical dashed line to indicate null effect 
    geom_vline(xintercept = 0, linetype = "dashed") +
    
    # add point estimate
    geom_point(aes(x = es, y = method_ordered)) +
    
    # add 95% CI
    geom_segment(aes(x = es - 1.96 * se, xend = es + 1.96 * se,
                     y = method_ordered, yend = method_ordered)) +
    
    # add labels
    geom_text(aes(x = es, y = method_ordered, label = label), vjust = -1.5) +
    
    # highlight selected estimation method
    gghighlight(method == estim(), 
                use_direct_label = FALSE,
                unhighlighted_params = list(color = "#525252")) +
    
    # set x-axis limits
    xlim(c(-1, 1)) +
    
    # set labels and title
    xlab("Effect size") + 
    ylab("Estimator") +
    ggtitle("Sensitivity Analysis Based on Estimation Method") +
    
    # set theme and center title
    theme_minimal() +
    theme(plot.title = element_text(hjust = 0.5))
})