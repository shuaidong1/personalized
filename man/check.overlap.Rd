% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/check_overlap.R
\name{check.overlap}
\alias{check.overlap}
\title{Check propensity score overlap}
\usage{
check.overlap(x, trt, propensity.func, type = c("histogram", "density",
  "both"), bins = 50L)
}
\arguments{
\item{x}{The design matrix (not including intercept term)}

\item{trt}{treatment vector with each element equal to a 0 or a 1, with 1 indicating
treatment status is active.}

\item{propensity.func}{function that inputs the design matrix x and the treatment vector trt and outputs
the propensity score, ie Pr(trt = 1 | X = x). Function should take two arguments 1) x and 2) trt. See example below.
For a randomized controlled trial this can simply be a function that returns a constant equal to the proportion
of patients assigned to the treatment group, i.e.:
\code{propensity.func = function(x, trt) 0.5}.}

\item{type}{Type of plot to create. Options are either a histogram (\code{type = "histogram"}) for each treatment
group, a density (\code{type = "density"}) for each treatment group, or to plot both a density and histogram
(\code{type = "code"})}

\item{bins}{integer number of bins for histograms when \code{type = "histogram"}}
}
\description{
Results in a plot to check whether the propensity score has adequate overlap between treatment groups
}
\examples{
library(personalized)

set.seed(123)
n.obs  <- 1000
n.vars <- 50
x <- matrix(rnorm(n.obs * n.vars, sd = 3), n.obs, n.vars)


# simulate non-randomized treatment
xbetat   <- 0.5 + 0.5 * x[,21] - 0.5 * x[,41]
trt.prob <- exp(xbetat) / (1 + exp(xbetat))
trt01    <- rbinom(n.obs, 1, prob = trt.prob)

# create function for fitting propensity score model
prop.func <- function(x, trt)
{
    # fit propensity score model
    propens.model <- cv.glmnet(y = trt,
                               x = x, family = "binomial")
    pi.x <- predict(propens.model, s = "lambda.min",
                    newx = x, type = "response")[,1]
    pi.x
}

check.overlap(x = x,
              trt = trt01,
              propensity.func = prop.func)

# now add density plot with histogram
check.overlap(x = x,
              trt = trt01,
              type = "both",
              propensity.func = prop.func)

}
