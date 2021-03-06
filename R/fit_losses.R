# Define common predictions function types
get.pred.func <- function(fit.name, model, env = parent.frame())
{
    n.trts    <- env$n.trts
    vnames    <- env$vnames
    sel.idx   <- env$sel.idx
    best.iter <- env$best.iter
    # GAM models
    if (grepl("_gam$",fit.name))
    {
        if (grepl("_cox", fit.name))
        {
            pred.func <- function(x)
            {
                df.pred <- data.frame(cbind(1, x[,sel.idx[-1] - 1]))
                colnames(df.pred) <- vnames
                -drop(predict(model, newdata = df.pred, type = "link"))
            }
        } else
        {
            pred.func <- function(x)
            {
                df.pred <- data.frame(cbind(1, x[,sel.idx[-1] - 1]))
                colnames(df.pred) <- vnames
                drop(predict(model, newdata = df.pred, type = "link"))
            }
        }
        # GBM models
    } else if (grepl("_gbm$",fit.name))
    {
        pred.func <- function(x) {
            df.x <- data.frame(cbind(1, x))
            colnames(df.x) <- vnames
            drop(predict(model, newdata = df.x, n.trees = best.iter, type = "link"))
        }
        # non-GAM/GBM LASSO models (loss ends in _lasso)
    } else if (grepl("_lasso$",fit.name))
    {
        if (grepl("_cox", fit.name))
        {
            pred.func <- function(x)
            {
                if (n.trts == 2)
                {
                    -drop(predict(model, newx = cbind(1, x), type = "link", s = "lambda.min"))
                } else
                {
                    ## need to handle cases with multiple treatments specially
                    ## because we don't want to sum up over all the estimated deltas.
                    ## for K-trtments we estimate K-1 delta functions and thus need
                    ## to extract each one individually.
                    all.coefs <- as.vector(predict(model, type = "coefficients", s = "lambda.min"))[-1]
                    n.coefs.per.trt <- length(all.coefs) / (n.trts - 1)

                    n.preds  <- NROW(x)
                    pred.mat <- array(NA, dim = c(n.preds, n.trts - 1))
                    for (t in 1:(n.trts - 1))
                    {
                        idx.coefs.cur <- (n.coefs.per.trt * (t - 1) + 1):(n.coefs.per.trt * t)
                        coefs.cur     <- all.coefs[idx.coefs.cur]

                        pred.mat[,t]  <- drop(cbind(1, x) %*% coefs.cur)
                    }
                    -pred.mat
                }
            }
        } else
        {
            pred.func <- function(x)
            {
                if (n.trts == 2)
                {
                    drop(predict(model, newx = cbind(1, x), type = "link", s = "lambda.min"))
                } else
                {
                    ## need to handle cases with multiple treatments specially
                    ## because we don't want to sum up over all the estimated deltas.
                    ## for K-trtments we estimate K-1 delta functions and thus need
                    ## to extract each one individually.
                    all.coefs <- as.vector(predict(model, type = "coefficients", s = "lambda.min"))[-1]
                    n.coefs.per.trt <- length(all.coefs) / (n.trts - 1)

                    n.preds  <- NROW(x)
                    pred.mat <- array(NA, dim = c(n.preds, n.trts - 1))
                    for (t in 1:(n.trts - 1))
                    {
                        idx.coefs.cur <- (n.coefs.per.trt * (t - 1) + 1):(n.coefs.per.trt * t)
                        coefs.cur     <- all.coefs[idx.coefs.cur]

                        pred.mat[,t]  <- drop(cbind(1, x) %*% coefs.cur)
                    }
                    pred.mat
                }
            }
        }
    } else
    {
        stop(paste0("No prediction method found for loss: ", fit.name))
    }
    return(pred.func)
} # End get.pred.func

# Define common coefficient return methods
get.coef.func <- function(fit.name, env = parent.frame())
{
    n.trts <- env$n.trts
    # GAM or LASSO_GAM models (using cv.glmnet())
    if ( grepl("_lasso$", fit.name) | grepl("lasso_gam$", fit.name) )
    {
        coef.func <- function(mod)
        {
            coef(mod, s = "lambda.min")
        }
        # LOSS_GAM models (using gam() )
    } else if ( grepl("_loss_gam$",fit.name) )
    {
        coef.func <- function(mod)
        {
            coef(mod)
        }
        # Not sure what the analogue is for GBM models, since there aren't any coefficients to return
    } else
    {
        coef.func <- function(mod)
        {
            return(NULL)
        }
    }
    return(coef.func)
} # End get.coef.func

#' @import glmnet
#' @importFrom stats coef
fit_sq_loss_lasso <- function(x, y, trt, n.trts, wts, family, ...)
{
  # this function must return a fitted model
  # in addition to a function which takes in
  # a design matrix and outputs estimated benefit scores

  ###################################################################
  ##
  ## IMPORTANT NOTE: the name of this function *must*
  ##                 begin with "fit_" and end with
  ##                 the text string to associated with
  ##                 this function in the options for the
  ##                 'loss' argument of the fit.subgrp()
  ##                 function
  ##
  ###################################################################


  list.dots <- list(...)
  dot.names <- names(list.dots)

  if ("penalty.factor" %in% dot.names)
  {
    ## ensure treatment is not penalized
    list.dots$penalty.factor[1] <- 0
  } else
  {
    list.dots$penalty.factor <- c(0, rep(1, ncol(x) - 1))
  }

  # fit a model with a lasso
  # penalty and desired loss
  model <- do.call(cv.glmnet, c(list(x = x, y = y, weights = wts, family = family,
                                     intercept = FALSE), list.dots))

  # Return fitted model and extraction methods
  list(predict      = get.pred.func("fit_sq_loss_lasso", model),
       model        = model,
       coefficients = get.coef.func("fit_sq_loss_lasso")(model))
}


fit_logistic_loss_lasso <- fit_sq_loss_lasso

#' @import survival
fit_cox_loss_lasso <- function(x, y, trt, n.trts, wts, family, ...)
{

  list.dots <- list(...)
  dot.names <- names(list.dots)

  if ("penalty.factor" %in% dot.names)
  {
    ## ensure treatment is not penalized
    list.dots$penalty.factor[1] <- 0
  } else
  {
    list.dots$penalty.factor <- c(0, rep(1, ncol(x) - 1))
  }

  # fit a model with a lasso
  # penalty and desired loss
  model <- do.call(cv.glmnet, c(list(x = x, y = y, weights = wts, family = "cox"), list.dots))

  # Return fitted model and extraction methods
  list(predict      = get.pred.func("fit_cox_loss_lasso", model),
       model        = model,
       coefficients = get.coef.func("fit_cox_loss_lasso")(model))
}


#' @import mgcv
#' @importFrom stats as.formula binomial gaussian
fit_sq_loss_lasso_gam <- function(x, y, trt, n.trts, wts, family, ...)
{
  # this function must return a fitted model
  # in addition to a function which takes in
  # a design matrix and outputs estimated benefit scores

  ###################################################################
  ##
  ## IMPORTANT NOTE: the name of this function *must*
  ##                 begin with "fit_" and end with
  ##                 the text string to associated with
  ##                 this function in the options for the
  ##                 'loss' argument of the fit.subgrp()
  ##                 function
  ##
  ###################################################################

  # need to inspect the dots to extract
  # the arguments supplied to cv.glmnet
  # and those supplied to gam
  list.dots <- list(...)
  dot.names <- names(list.dots)

  if ("penalty.factor" %in% dot.names)
  {
    ## ensure treatment is not penalized
    list.dots$penalty.factor[1] <- 0
  } else
  {
    list.dots$penalty.factor <- c(0, rep(1, ncol(x) - 1))
  }

  glmnet.argnames <- union(names(formals(cv.glmnet)), names(formals(glmnet)))
  gam.argnames    <- names(formals(gam))



  # since 'method' is an argument of 'fit.subgrp',
  # let the user change the gam 'method' arg by supplying
  # 'method.gam' arg instead of 'method'
  dot.names[dot.names == "method.gam"] <- "method"
  names(list.dots)[names(list.dots) == "method.gam"] <- "method"




  # find the arguments relevant for each
  # possible ...-supplied function
  dots.idx.glmnet <- match(glmnet.argnames, dot.names)
  dots.idx.gam    <- match(gam.argnames, dot.names)

  dots.idx.glmnet <- dots.idx.glmnet[!is.na(dots.idx.glmnet)]
  dots.idx.gam    <- dots.idx.gam[!is.na(dots.idx.gam)]

  # fit a model with a lasso
  # penalty and desired loss:
  # only add in dots calls if they exist
  if (length(dots.idx.glmnet) > 0)
  {
    sel.model <- do.call(cv.glmnet, c(list(x = x, y = y, weights = wts, family = family,
                                           intercept = FALSE), list.dots[dots.idx.glmnet]))
  } else
  {
    sel.model <- do.call(cv.glmnet, list(x = x, y = y, weights = wts, family = family,
                                         intercept = FALSE))
  }

  vnames <- colnames(x)

  sel.idx <- drop(predict(sel.model, type = "nonzero", s = "lambda.min")[[1]])

  # always include treatment main effect
  sel.idx <- union(1L, sel.idx)

  # names of selected variables
  sel.vnames <- vnames[sel.idx]

  # find which variables are binary
  var.levels <- numeric(length(sel.idx))
  for (v in 1:length(sel.idx))
  {
    var.levels[v] <- length(unique(x[,sel.idx[v]]))
  }

  contin.vars <- sel.vnames[var.levels > 2]
  binary.vars <- sel.vnames[var.levels == 2]

  # create formula for gam
  contin.formula <- binary.formula <- NULL

  # don't create smoother for binary vars
  if (length(binary.vars) > 0)
  {
    binary.formula <- paste(binary.vars, collapse = "+")
  }

  # create smoother for each continuous var
  if (length(contin.vars) > 0)
  {
    form.cur <- paste0("s(", contin.vars, ")")
    contin.formula <- paste(form.cur, collapse = "+")
  }

  family.func <- gaussian()

  if (family == "cox")
  {
    rhs.formula <- paste(c(binary.formula, contin.formula), collapse = "+")
    family.func <- cox.ph()
  } else
  {
    rhs.formula <- paste("-1 +", paste(c(binary.formula, contin.formula), collapse = "+"))
    if (family == "binomial")
    {
      family.func <- binomial()
      y <- as.integer(y)
    }
  }
  gam.formula <- as.formula(paste("y ~", rhs.formula))

  # create data frame
  df <- data.frame(y = y, x = x[,sel.idx])
  colnames(df) <- c("y", sel.vnames)

  vnames <- sel.vnames

  # fit gam model:
  # only add in dots calls if they exist
  if (length(dots.idx.glmnet) > 0)
  {
    model <- do.call(gam, c(list(formula = gam.formula, data = df,
                                 weights = wts, family = family.func,
                                 drop.intercept = TRUE),
                            list.dots[dots.idx.gam]))
  } else
  {
    model <- do.call(gam, list(formula = gam.formula, data = df,
                               weights = wts, family = family.func,
                               drop.intercept = TRUE))
  }

  # Return fitted model and extraction methods
  list(predict      = get.pred.func("fit_sq_loss_lasso_gam", model),
       model        = model,
       coefficients = get.coef.func("fit_sq_loss_lasso_gam")(model))
}

fit_logistic_loss_lasso_gam <- fit_sq_loss_lasso_gam
fit_cox_loss_lasso_gam      <- fit_sq_loss_lasso_gam



fit_sq_loss_gam <- function(x, y, trt, n.trts, wts, family, ...)
{
  # this function must return a fitted model
  # in addition to a function which takes in
  # a design matrix and outputs estimated benefit scores

  ###################################################################
  ##
  ## IMPORTANT NOTE: the name of this function *must*
  ##                 begin with "fit_" and end with
  ##                 the text string to associated with
  ##                 this function in the options for the
  ##                 'loss' argument of the fit.subgrp()
  ##                 function
  ##
  ###################################################################


  list.dots <- list(...)

  # since 'method' is an argument of 'fit.subgrp',
  # let the user change the gam 'method' arg by supplying
  # 'method.gam' arg instead of 'method'
  names(list.dots)[names(list.dots) == "method.gam"] <- "method"

  vnames  <- colnames(x)
  sel.idx <- seq_len(ncol(x))

  # names of selected variables
  sel.vnames <- vnames[sel.idx]

  # find which variables are binary
  var.levels <- numeric(length(sel.idx))
  for (v in 1:length(sel.idx))
  {
    var.levels[v] <- length(unique(x[,sel.idx[v]]))
  }

  contin.vars <- sel.vnames[var.levels > 2]
  binary.vars <- sel.vnames[var.levels == 2]

  # create formula for gam
  contin.formula <- binary.formula <- NULL

  # don't create smoother for binary vars
  if (length(binary.vars) > 0)
  {
    binary.formula <- paste(binary.vars, collapse = "+")
  }

  # create smoother for each continuous var
  if (length(contin.vars) > 0)
  {
    form.cur <- paste0("s(", contin.vars, ")")
    contin.formula <- paste(form.cur, collapse = "+")
  }

  family.func <- gaussian()

  if (family == "cox")
  {
    rhs.formula <- paste(c(binary.formula, contin.formula), collapse = "+")
    family.func <- cox.ph()
  } else
  {
    rhs.formula <- paste("-1 +", paste(c(binary.formula, contin.formula), collapse = "+"))
    if (family == "binomial")
    {
      family.func <- binomial()
      y <- as.integer(y)
    }
  }
  gam.formula <- as.formula(paste("y ~", rhs.formula))

  # create data frame
  df <- data.frame(y = y, x = x[,sel.idx])
  colnames(df) <- c("y", sel.vnames)

  vnames <- sel.vnames

  # fit gam model:
  # only add in dots calls if they exist
  if (length(list.dots) > 0)
  {
    model <- do.call(gam, c(list(formula = gam.formula, data = df,
                                 weights = wts, family = family.func,
                                 drop.intercept = TRUE),
                            list.dots))
  } else
  {
    model <- do.call(gam, list(formula = gam.formula, data = df,
                               weights = wts, family = family.func,
                               drop.intercept = TRUE))
  }


  # Return fitted model and extraction methods
  list(predict      = get.pred.func("fit_sq_loss_gam", model),
       model        = model,
       coefficients = get.coef.func("fit_sq_loss_gam")(model))
}

fit_logistic_loss_gam <- fit_sq_loss_gam
fit_cox_loss_gam      <- fit_sq_loss_gam



#' @import gbm
fit_sq_loss_gbm <- function(x, y, trt, n.trts, wts, family, ...)
{
  # this function must return a fitted model
  # in addition to a function which takes in
  # a design matrix and outputs estimated benefit scores

  ###################################################################
  ##
  ## IMPORTANT NOTE: the name of this function *must*
  ##                 begin with "fit_" and end with
  ##                 the text string to associated with
  ##                 this function in the options for the
  ##                 'loss' argument of the fit.subgrp()
  ##                 function
  ##
  ###################################################################

  list.dots <- list(...)

  dot.names <- names(list.dots)
  if ("cv.folds" %in% dot.names)
  {
    cv.folds <- list.dots["cv.folds"]
    if (cv.folds < 2)
    {
      cv.folds <- 2L
      list.dots$cv.folds <- cv.folds
      warning("cv.folds must be at least 2")
    }

  } else
  {
    list.dots$cv.folds <- 5L
  }


  df <- data.frame(y = y, x)

  formula.gbm <- as.formula("y ~ . - 1")

  # fit a model with a lasso
  # penalty and desired loss
  model <- do.call(gbm, c(list(formula.gbm, data = df,
                               weights = wts,
                               distribution = "gaussian"),
                          list.dots))

  best.iter <- gbm.perf(model, method = "cv")

  vnames <- colnames(df)[-1]

  # Return fitted model and extraction methods
  list(predict      = get.pred.func("fit_sq_loss_gbm", model),
       model        = model,
       coefficients = get.coef.func("fit_sq_loss_gbm")(model))
}


fit_abs_loss_gbm <- function(x, y, trt, n.trts, wts, family, ...)
{
  # this function must return a fitted model
  # in addition to a function which takes in
  # a design matrix and outputs estimated benefit scores

  ###################################################################
  ##
  ## IMPORTANT NOTE: the name of this function *must*
  ##                 begin with "fit_" and end with
  ##                 the text string to associated with
  ##                 this function in the options for the
  ##                 'loss' argument of the fit.subgrp()
  ##                 function
  ##
  ###################################################################

  list.dots <- list(...)

  dot.names <- names(list.dots)
  if ("cv.folds" %in% dot.names)
  {
    cv.folds <- list.dots["cv.folds"]
    if (cv.folds < 2)
    {
      cv.folds <- 2L
      list.dots$cv.folds <- cv.folds
      warning("cv.folds must be at least 2")
    }

  } else
  {
    list.dots$cv.folds <- 5L
  }


  df <- data.frame(y = y, x)

  formula.gbm <- as.formula("y ~ . - 1")

  # fit a model with a lasso
  # penalty and desired loss
  model <- do.call(gbm, c(list(formula.gbm, data = df,
                               weights = wts,
                               distribution = "laplace"),
                          list.dots))

  best.iter <- gbm.perf(model, method = "cv")

  vnames <- colnames(df)[-1]

  # Return fitted model and extraction methods
  list(predict      = get.pred.func("fit_abs_loss_gbm", model),
       model        = model,
       coefficients = get.coef.func("fit_abs_loss_gbm")(model))
}


fit_logistic_loss_gbm <- function(x, y, trt, n.trts, wts, family, ...)
{
  # this function must return a fitted model
  # in addition to a function which takes in
  # a design matrix and outputs estimated benefit scores

  ###################################################################
  ##
  ## IMPORTANT NOTE: the name of this function *must*
  ##                 begin with "fit_" and end with
  ##                 the text string to associated with
  ##                 this function in the options for the
  ##                 'loss' argument of the fit.subgrp()
  ##                 function
  ##
  ###################################################################

  list.dots <- list(...)

  dot.names <- names(list.dots)
  if ("cv.folds" %in% dot.names)
  {
    cv.folds <- list.dots["cv.folds"]
    if (cv.folds < 2)
    {
      cv.folds <- 2L
      list.dots$cv.folds <- cv.folds
      warning("cv.folds must be at least 2")
    }

  } else
  {
    list.dots$cv.folds <- 5L
  }


  df <- data.frame(y = y, x)

  formula.gbm <- as.formula("y ~ . - 1")

  # fit a model with a lasso
  # penalty and desired loss
  model <- do.call(gbm, c(list(formula.gbm, data = df,
                               weights = wts,
                               distribution = "bernoulli"),
                          list.dots))

  best.iter <- gbm.perf(model, method = "cv")

  vnames <- colnames(df)[-1]

  # Return fitted model and extraction methods
  list(predict      = get.pred.func("fit_logistic_loss_gbm", model),
       model        = model,
       coefficients = get.coef.func("fit_logistic_loss_gbm")(model))
}


fit_huberized_loss_gbm <- function(x, y, trt, n.trts, wts, family, ...)
{
  # this function must return a fitted model
  # in addition to a function which takes in
  # a design matrix and outputs estimated benefit scores

  ###################################################################
  ##
  ## IMPORTANT NOTE: the name of this function *must*
  ##                 begin with "fit_" and end with
  ##                 the text string to associated with
  ##                 this function in the options for the
  ##                 'loss' argument of the fit.subgrp()
  ##                 function
  ##
  ###################################################################

  list.dots <- list(...)

  dot.names <- names(list.dots)
  if ("cv.folds" %in% dot.names)
  {
    cv.folds <- list.dots["cv.folds"]
    if (cv.folds < 2)
    {
      cv.folds <- 2L
      list.dots$cv.folds <- cv.folds
      warning("cv.folds must be at least 2")

    }

  } else
  {
    list.dots$cv.folds <- 5L
  }


  df <- data.frame(y = y, x)

  formula.gbm <- as.formula("y ~ . - 1")

  # fit a model with a lasso
  # penalty and desired loss
  model <- do.call(gbm, c(list(formula.gbm, data = df,
                               weights = wts,
                               distribution = "huberized"),
                          list.dots))

  best.iter <- gbm.perf(model, method = "cv")

  vnames <- colnames(df)[-1]

  # Return fitted model and extraction methods
  list(predict      = get.pred.func("fit_huberized_loss_gbm", model),
       model        = model,
       coefficients = get.coef.func("fit_huberized_loss_gbm")(model))
}


fit_cox_loss_gbm <- function(x, y, trt, n.trts, wts, family, ...)
{
  # this function must return a fitted model
  # in addition to a function which takes in
  # a design matrix and outputs estimated benefit scores

  ###################################################################
  ##
  ## IMPORTANT NOTE: the name of this function *must*
  ##                 begin with "fit_" and end with
  ##                 the text string to associated with
  ##                 this function in the options for the
  ##                 'loss' argument of the fit.subgrp()
  ##                 function
  ##
  ###################################################################

  list.dots <- list(...)

  dot.names <- names(list.dots)
  if ("cv.folds" %in% dot.names)
  {
    cv.folds <- list.dots["cv.folds"]
    if (cv.folds < 2)
    {
      cv.folds <- 2L
      list.dots$cv.folds <- cv.folds
      warning("cv.folds must be at least 2")
    }

  } else
  {
    list.dots$cv.folds <- 5L
  }

  surv.vnames <- colnames(y)

  time.idx   <- which(surv.vnames == "time")
  status.idx <- which(surv.vnames == "status")

  df <- data.frame(cox_gbm_time = y[,time.idx], cox_gbm_status = y[,status.idx], x)

  formula.gbm <- as.formula("Surv(cox_gbm_time, cox_gbm_status) ~ . - 1")

  # fit a model with a lasso
  # penalty and desired loss
  model <- do.call(gbm, c(list(formula.gbm, data = df,
                               weights = wts,
                               distribution = "coxph"),
                          list.dots))

  best.iter <- gbm.perf(model, method = "cv")

  vnames <- colnames(df)[-c(1,2)]

  # Return fitted model and extraction methods
  list(predict      = get.pred.func("fit_cox_loss_gbm", model),
       model        = model,
       coefficients = get.coef.func("fit_cox_loss_gbm")(model))
}


