#' Plotting validation results for fitted subgroup identification models
#'
#' @description Plots validation results for estimated subgroup treatment effects
#'
#' @param x fitted object returned by \code{validate.subgroup()} or \code{fit.subgroup()} function
#' @param type type of plot. \code{"density"} results in a density plot for the results
#' across all observations (if \code{x} is from \code{fit.subgroup()}) or if \code{x} is from \code{validate.subgroup()}
#' across iterations of either the bootstrap or training/test re-fitting. For the latter
#' case the test results will be plotted. \code{"boxplot"} results in boxplots across all observations/iterations of either
#' the bootstrap or training/test re-fitting. For the latter
#' case the test results will be plotted. \code{"interaction"} creates an
#' interaction plot for the different subgroups (crossing lines here means a meaningful subgroup)
#' @param avg.line boolean value of whether or not to plot a line for the average
#' value in addition to the density (only valid for \code{type = "density"})
#' @param ... not used
#' @seealso \code{\link[personalized]{validate.subgroup}} for function which creates validation results
#' and \code{\link[personalized]{fit.subgroup}} for function which fits subgroup identification models.
#' @rdname plot
#' @import plotly
#' @importFrom ggplot2 ggplot aes geom_density geom_rug coord_flip facet_grid theme xlab
#' @importFrom ggplot2 ylab ggtitle geom_vline geom_boxplot geom_line geom_point
#' @importFrom ggplot2 scale_x_discrete geom_histogram geom_rect geom_hline xlim geom_bar
#'
#' @examples
#'
#' valmod <- validate.subgroup(subgrp.model, B = 5,
#'                           method = "training_test",
#'                           train.fraction = 0.75)
#' valmod$avg.results
#'
#' plot(valmod)
#'
#' plot(valmod, type = "boxplot")
#'
#' plot(valmod, type = "interaction")
#'
#' @export
plot.subgroup_validated <- function(x,
                                    type = c("boxplot", "density", "interaction", "stability"),
                                    avg.line = TRUE,
                                    ...)
{
    type <- match.arg(type)

    family   <- x$family

    avg.line <- as.logical(avg.line[1])

    boot.res <- x$boot.results$avg.outcomes
    avg.res  <- x$avg.results

    boot.dims <- dim(boot.res)

    n.entries <- prod(boot.dims[2:3])
    B <- boot.dims[1]

    res.2.plot <- array(NA, dim = c(B * n.entries, 3))
    colnames(res.2.plot) <- c("Recommended", "Received", "Value")
    res.2.plot <- data.frame(res.2.plot)

    avg.res.2.plot <- data.frame(Recommended = rep(colnames(avg.res$avg.outcomes),
                                                   each = ncol(avg.res$avg.outcomes)),
                                 Received    = rep(rownames(avg.res$avg.outcomes),
                                                   ncol(avg.res$avg.outcomes)),
                                 Value       = as.vector(avg.res$avg.outcomes))

    Recommended <- Received <- Value <- NULL

    for (b in 1:B)
    {
        cur.idx <- c(((b - 1) * n.entries + 1):(b * n.entries))
        res.2.plot[cur.idx, 1] <- rep(colnames(boot.res[b,,]),
                                      each = ncol(boot.res[b,,]))
        res.2.plot[cur.idx, 2] <- rep(rownames(boot.res[b,,]),
                                      ncol(boot.res[b,,]))
        res.2.plot[cur.idx, 3] <- as.vector(boot.res[b,,])
    }


    title.text <- NULL
    if (x$val.method == "training_test_replication")
    {
        title.text <- "Average Test Set Outcome Across Replications Among Subgroups"
    } else
    {
        title.text <- "Average Bias-Corrected Outcome Across Replications Among Subgroups"
    }

    ylab.text <- "Average Outcome"

    if (family == "cox")
    {
        ylab.text <- "Average Restricted Mean"
    }

    if (type == "density")
    {
        pl.obj <- ggplot(res.2.plot,
                         aes(x = Value, fill = Received)) +
            geom_density(alpha = 0.65) +
            geom_rug(aes(colour = Received), alpha = 0.85) +
            coord_flip() +
            facet_grid( ~ Recommended) +
            theme(legend.position = "bottom") +
            xlab(ylab.text) +
            ggtitle(title.text)
        if (avg.line)
        {
            pl.obj <- pl.obj + geom_vline(data = avg.res.2.plot,
                                          aes(xintercept = Value),
                                          size = 1.25) +
                geom_vline(data = avg.res.2.plot,
                           aes(xintercept = Value, colour = Received))
        }
    } else if (type == "boxplot")
    {
        pl.obj <- ggplot(res.2.plot,
                         aes(x = Received, y = Value)) +
            geom_boxplot(aes(fill = Received)) +
            geom_rug(aes(colour = Received), alpha = 0.85) +
            facet_grid( ~ Recommended) +
            theme(legend.position = "bottom") +
            ylab(ylab.text) +
            ggtitle(title.text)
    } else if (type == "stability")
    {
        # Acquire coefficients for each bootstrap iteration (exclude Intercept and Trt terms)
        d <- as.data.frame(x$boot.results[[4]][-c(1,2),])

        pct.selected <- is.consistent <- med <- bar.type <- name <- plot.idx <- NULL

        # Compute percentage of times each variable was selected
        d$pct.selected <- apply(d,1,function(x){sum(x!=0)}/ncol(d)*100)

        # Remove instances where variables were never selected in any bootstrap iteration
        d <- subset(d, pct.selected != 0)

        # Compute percentage of time variable has consistent sign.
        # A variable is deemed consistent if it has the same sign at least 95% of the times it was selected.
        signs <- apply(d[,grep("B",colnames(d), value=T)],1,function(x){sign(x)[x!=0]})
        d$is.consistent <- sapply(signs,function(x){any(table(x) / length(x) >= .95)})

        # Calculate min, median, and max
        summary.stats <- apply(d[,grep("B",colnames(d), value=TRUE)],1,function(x){summary(x[x!=0])})
        d$min <- summary.stats["Min.",]
        d$med <- summary.stats["Median",]
        d$max <- summary.stats["Max.",]

        # Create label for bar type (Positive/Negative Tendency or Mixed)
        d$bar.type <- factor(ifelse(d$is.consistent, ifelse(d$med > 0,"Positive Tendency","Negative Tendency"),"Mixed"),
                             levels=c("Negative Tendency", "Mixed", "Positive Tendency"))

        # Order by most frequently selected and bar type
        d <- d[order(d$bar.type,-d$pct.selected),]

        # Add variable name and plot index to data for plotting purposes
        d$name <- rownames(d)
        d$plot.idx <- 1:nrow(d)

        # Remove individual bootstrap values from plotting data frame
        d <- d[,!(names(d) %in% grep("B",names(d),value=TRUE))]

        # Primary Plot - Range with median points
        p.primary <- ggplot(data = d) +
            geom_rect(mapping = aes(xmin = plot.idx-0.5, xmax=plot.idx+0.5, ymin = min, ymax = max, fill = bar.type), color="black", stat="identity") +
            geom_point(mapping = aes(x=plot.idx, y = med), size= 1.5, shape=21, color="black", fill="purple", stat="identity") +
            geom_hline(yintercept = 0) +
            geom_vline(xintercept = c(which.min(d$bar.type=="Negative Tendency") - 0.5, which.max(d$bar.type=="Positive Tendency") - 0.5), linetype = "dashed") +
            xlim(0,nrow(d)+1)

        # Secondary Plot - Distribution of selection probability
        p.secondary <- ggplot(data = d) +
            geom_bar(mapping = aes(x = plot.idx, y = pct.selected, fill = bar.type), stat="identity") +
            geom_vline(xintercept = c(which.min(d$bar.type=="Negative Tendency") - 0.5, which.max(d$bar.type=="Positive Tendency") - 0.5), linetype = "dashed")

        # Construct textbox for tooltips
        tooltip.txt <- paste("Variable:", d$name, "\n",
                             "Selection :", paste0(d$pct.selected,"%"), "\n",
                             "Median:", round(d$med,5), "\n",
                             "Range:", paste0("[",round(d$min,5),",",round(d$max,5),"]"))

        # Enforce tooltips
        pp.primary=plotly_build(p.primary)
        ppp.primary <- style(pp.primary, text=tooltip.txt, hoverinfo = "text")

        pp.secondary=plotly_build(p.secondary)
        ppp.secondary <- style(pp.secondary, text=tooltip.txt, hoverinfo = "none")

        # Plot primary and secondary plots together, and label axes
        pl.obj <- subplot(ppp.primary, ppp.secondary, nrows=2, shareX=TRUE, titleX = TRUE, titleY = TRUE) %>%
            layout(title="Variable Selection Across Bootstrap Iterations",
                   showlegend=FALSE,
                   xaxis =  list(title = "Plot Index"),
                   yaxis =  list(title="Coefficient Value"),
                   yaxis2 = list(title="Percent of Times Selected"))
    } else
    {
        pl.obj <- ggplot(avg.res.2.plot,
                         aes(x = Recommended, y = Value, group = Received)) +
            geom_line(aes(colour = Received), size = 1.25) +
            geom_point(aes(colour = Received), size = 2) +
            theme(legend.position = "bottom") +
            scale_x_discrete(expand = c(0.25, 0.25)) +
            ylab(ylab.text) +
            ggtitle(title.text)
    }
    # Return plot
    pl.obj

}
