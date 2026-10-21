# House visualization defaults ------------------------------------------------

#' House ggplot2 theme
#'
#' A clean minimal theme used across project figures: no minor grid, muted axis
#' titles, left-aligned plot title.
#'
#' @param base_size Base font size (default 12).
#' @param base_family Base font family (default "").
#' @return A ggplot2 theme object.
#' @examples
#' library(ggplot2)
#' ggplot(mtcars, aes(wt, mpg)) + geom_point() + theme_dc()
#' @export
theme_dc <- function(base_size = 12, base_family = "") {
  ggplot2::theme_minimal(base_size = base_size, base_family = base_family) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(face = "bold", hjust = 0),
      plot.title.position = "plot",
      axis.title = ggplot2::element_text(colour = "grey30"),
      legend.position = "bottom"
    )
}

#' Descriptive "Table 1" via gtsummary
#'
#' Thin wrapper around [gtsummary::tbl_summary()] that applies project defaults
#' (median [IQR] for continuous, n (%) for categorical) and optionally adds an
#' overall column and a by-group p-value. Requires the `gtsummary` package.
#'
#' @param data A data frame.
#' @param by Optional grouping column, given as a string.
#' @param include Optional character vector of columns to include (default: all).
#' @param add_overall Logical; add an overall column (default `TRUE` when `by`
#'   is supplied).
#' @param add_p Logical; add a group comparison p-value (default `FALSE`).
#' @return A `gtsummary` table object.
#' @export
tbl1 <- function(data, by = NULL, include = NULL,
                 add_overall = !is.null(by), add_p = FALSE) {
  if (!requireNamespace("gtsummary", quietly = TRUE)) {
    cli::cli_abort("{.fn tbl1} requires the {.pkg gtsummary} package.")
  }
  args <- list(
    data = data,
    statistic = list(
      gtsummary::all_continuous() ~ "{median} [{p25}, {p75}]",
      gtsummary::all_categorical() ~ "{n} ({p}%)"
    )
  )
  if (!is.null(by)) args$by <- by
  if (!is.null(include)) args$include <- include
  tbl <- do.call(gtsummary::tbl_summary, args)
  if (isTRUE(add_overall) && !is.null(by)) tbl <- gtsummary::add_overall(tbl)
  if (isTRUE(add_p) && !is.null(by)) tbl <- gtsummary::add_p(tbl)
  tbl
}
