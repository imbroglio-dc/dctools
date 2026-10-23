# Small-count suppression for reports (internal) ------------------------
#
# Ported unchanged in behaviour from sepsis_burn
# code/functions/disclosure_safe_report.R (commit 0cd21c0), lines 167-673:
# deciding which counts to hide, and resolving {{id}} placeholders. The
# rules are documented in R/report.R.

# ---- Deciding what to hide ----

# A generous upper bound assumed for any count.
.count_upper_bound <- function(report) {
  largest <- max(c(report$counts, report$unprinted_counts, 0), na.rm = TRUE)
  2 * largest + 10
}

# The relations as a sparse matrix: one row per relation, one column per id
# (`all_ids`), holding the non-zero coefficients. Stored by column
# (`rows_of_column`, `values_of_column`) and by row (`columns_of_row`), because
# a report can have thousands of relations and ids, and a dense matrix of that
# size is slow to copy and scan on every pass of `.decide_which_counts_to_hide()`.
.index_relation_coefficients <- function(relations, all_ids) {
  coefficients <- lapply(relations, function(relation) {
    kept <- relation$coefficients
    kept <- kept[!duplicated(names(kept), fromLast = TRUE)] # last one wins
    kept[!is.na(kept) & kept != 0]
  })
  row_numbers <- rep(seq_along(coefficients), lengths(coefficients))
  column_numbers <- match(
    unlist(lapply(coefficients, names), use.names = FALSE),
    all_ids
  )
  # as.numeric(): with no relations unlist() gives NULL, which split() rejects.
  values <- as.numeric(unlist(coefficients, use.names = FALSE))
  by_column <- factor(column_numbers, levels = seq_along(all_ids))
  list(
    ids = all_ids,
    n_rows = length(relations),
    columns_of_row = split(
      column_numbers,
      factor(row_numbers, levels = seq_along(relations))
    ),
    rows_of_column = unname(split(row_numbers, by_column)),
    values_of_column = unname(split(values, by_column))
  )
}

# A function that looks for integer amounts by which the `movable_ids` could
# move so that the count `small_id` moves with them and every relation still
# holds. Returns those amounts (zero for counts that stay put), or NULL if
# there are none. Relations that share a movable count depend on each other;
# each group of dependent relations is found (only when a small count first
# touches it) and solved on its own, and its matrix factorisation is kept, so
# many small counts in the same group cost one factorisation, not one each.
#
# `excluded_id` (one of `movable_ids`) is held fixed for that call only: the
# groups are still those of all `movable_ids`, and only the group holding the
# excluded count is factorised again without it. A group that could be split
# once that count is removed is then solved as one block, which gives the same
# answer: its parts share no relation, so `qr()` treats them independently.
# This lets one finder serve every small count ("the other small counts may
# move, this one may not") instead of building a new finder per small count.
.make_shift_finder <- function(relation_coefficients, movable_ids) {
  ids <- relation_coefficients$ids
  columns_of_row <- relation_coefficients$columns_of_row
  rows_of_column <- relation_coefficients$rows_of_column
  values_of_column <- relation_coefficients$values_of_column
  # For each column: its position in `movable_ids`, NA if it cannot move.
  movable_position <- rep(NA_integer_, length(ids))
  movable_position[match(movable_ids, ids)] <- seq_along(movable_ids)
  # For each row: its group, 0 once known to hold no movable count, NA until
  # a small count first reaches it.
  group_of_row <- rep(NA_integer_, relation_coefficients$n_rows)
  groups <- list()

  # A group's rows and columns in their original order, which is the order
  # `qr()` sees them in (it decides which columns are left out when the
  # relations are not independent).
  group_matrix <- function(rows, columns) {
    group_values <- matrix(0, length(rows), length(columns))
    for (j in seq_along(columns)) {
      in_group <- match(rows_of_column[[columns[j]]], rows)
      group_values[in_group, j] <- values_of_column[[columns[j]]]
    }
    group_values
  }
  solve_group <- function(rows, columns, values = group_matrix(rows, columns)) {
    list(
      rows = rows,
      columns = columns,
      matrix = values,
      factorisation = qr(values)
    )
  }

  # Every row linked to `first_row` through movable counts, and those counts.
  group_containing <- function(first_row) {
    if (is.na(group_of_row[first_row])) {
      rows <- first_row
      columns <- integer(0)
      frontier_rows <- first_row
      while (length(frontier_rows) > 0L) {
        linked_columns <- unique(unlist(
          columns_of_row[frontier_rows],
          use.names = FALSE
        ))
        linked_columns <- linked_columns[
          !is.na(movable_position[linked_columns])
        ]
        new_columns <- setdiff(linked_columns, columns)
        columns <- c(columns, new_columns)
        linked_rows <- unique(unlist(
          rows_of_column[new_columns],
          use.names = FALSE
        ))
        frontier_rows <- setdiff(linked_rows, rows)
        rows <- c(rows, frontier_rows)
      }
      if (length(columns) == 0L) {
        group_of_row[first_row] <<- 0L
      } else {
        rows <- sort(rows)
        columns <- columns[order(movable_position[columns])]
        groups[[length(groups) + 1L]] <<- solve_group(rows, columns)
        group_of_row[rows] <<- length(groups)
      }
    }
    group_of_row[first_row]
  }

  function(small_id, excluded_id = NULL) {
    small_column <- match(small_id, ids)
    small_rows <- rows_of_column[[small_column]]
    small_values <- values_of_column[[small_column]]
    excluded_column <- match(excluded_id, ids)
    shifts <- numeric(length(movable_ids))
    for (small_row in small_rows) {
      if (group_containing(small_row) == 0L) {
        return(NULL) # a relation that no movable count can help to balance
      }
    }
    for (group in unique(group_of_row[small_rows])) {
      group_data <- groups[[group]]
      is_excluded <- group_data$columns %in% excluded_column
      if (any(is_excluded)) {
        if (all(is_excluded)) {
          return(NULL) # only the excluded count could balance these relations
        }
        group_data <- solve_group(
          group_data$rows,
          group_data$columns[!is_excluded],
          group_data$matrix[, !is_excluded, drop = FALSE]
        )
      }
      group_small_column <- numeric(length(group_data$rows))
      in_group <- match(small_rows, group_data$rows)
      group_small_column[in_group[!is.na(in_group)]] <- small_values[
        !is.na(in_group)
      ]
      direction <- qr.coef(group_data$factorisation, -group_small_column)
      direction[is.na(direction)] <- 0
      direction <- round(direction)
      residual <- group_data$matrix %*% direction + group_small_column
      if (max(abs(residual)) > 1e-8) {
        return(NULL)
      }
      shifts[movable_position[group_data$columns]] <- direction
    }
    shifts
  }
}

# A function that says, for a small ("<5") count, whether it is consistent with
# every value 1-4, given what is hidden (TRUE = the reader cannot narrow it
# down). This is a sufficient test, not a necessary one: it looks for an
# integer "direction" in which the small count and some hidden counts can all
# move together while every relation still holds and every moved count stays
# inside the range a reader knows it to be in:
#   printed-as-"<5" counts 1-4; "<suppr." counts 5 up to the upper bound;
#   unprinted ("~") quantities 0 up to the upper bound.
#
# The hidden counts that could move are the same for every small count, so the
# work on them is shared (see `.make_shift_finder()`); only the small count's own
# column changes. That is what keeps a report with thousands of counts fast.
.make_small_count_checker <- function(
  report,
  relation_coefficients,
  suppressed_ids,
  small_ids,
  unprinted_ids,
  upper_bound
) {
  counts <- report$counts
  largest_shift <- .disclosure_threshold - 2L

  # All vectorised over ids: they run for every movable count on every pass.
  values_of <- function(ids) {
    values <- unname(counts[ids])
    is_unprinted <- startsWith(ids, "~")
    values[is_unprinted] <- unname(report$unprinted_counts[ids[is_unprinted]])
    values
  }
  lowest_possible <- function(ids) {
    ifelse(
      startsWith(ids, "~"),
      0,
      ifelse(ids %in% small_ids, 1, .disclosure_threshold)
    )
  }
  highest_possible <- function(ids) {
    ifelse(ids %in% small_ids, .disclosure_threshold - 1L, upper_bound)
  }
  has_room_to_move <- function(ids) {
    values <- values_of(ids)
    !is.na(values) &
      (values - lowest_possible(ids)) >= largest_shift &
      (highest_possible(ids) - values) >= largest_shift
  }

  # Can `small_id` shift by some integer combination of `movable_ids`
  # without leaving the ranges the reader knows? `find_shifts` comes from
  # `.make_shift_finder()` for those ids.
  can_shift_using <- function(
    movable_ids,
    find_shifts,
    small_id,
    shifts_to_other_values,
    excluded_id = NULL
  ) {
    if (length(setdiff(movable_ids, excluded_id)) == 0L) {
      return(FALSE)
    }
    direction <- find_shifts(small_id, excluded_id)
    if (is.null(direction)) {
      return(FALSE)
    }
    is_moved <- direction != 0
    moved_ids <- movable_ids[is_moved]
    values <- values_of(moved_ids)
    if (anyNA(values)) {
      return(FALSE)
    }
    # One row per moved count, one column per other value of the small count.
    shifted_values <- values +
      outer(direction[is_moved], shifts_to_other_values)
    !any(
      shifted_values < lowest_possible(moved_ids) |
        shifted_values > highest_possible(moved_ids)
    )
  }

  movable_ids <- unique(c(suppressed_ids, unprinted_ids))
  movable_ids <- movable_ids[has_room_to_move(movable_ids)]
  find_shifts_of_hidden_counts <- .make_shift_finder(
    relation_coefficients,
    movable_ids
  )
  # Built on first use, then shared by every small count: each call holds that
  # small count itself fixed (see `.make_shift_finder()`'s `excluded_id`).
  with_small_ids <- c(movable_ids, small_ids)
  find_shifts_with_small_counts <- NULL

  function(small_id) {
    small_column <- match(small_id, relation_coefficients$ids)
    if (length(relation_coefficients$rows_of_column[[small_column]]) == 0L) {
      return(TRUE) # in no relation: nothing to recover
    }
    own_value <- counts[[small_id]]
    shifts_to_other_values <-
      setdiff(1:(.disclosure_threshold - 1L), own_value) - own_value

    # First try with hidden counts only; if that fails, let the other small
    # counts move too (they must stay within 1-4).
    if (
      can_shift_using(
        movable_ids,
        find_shifts_of_hidden_counts,
        small_id,
        shifts_to_other_values
      )
    ) {
      return(TRUE)
    }
    if (is.null(find_shifts_with_small_counts)) {
      find_shifts_with_small_counts <<- .make_shift_finder(
        relation_coefficients,
        with_small_ids
      )
    }
    can_shift_using(
      with_small_ids,
      find_shifts_with_small_counts,
      small_id,
      shifts_to_other_values,
      excluded_id = small_id
    )
  }
}

# For each relation, the ids it mentions; for each id, the relations that
# mention it (ids in no relation are absent).
.index_relations <- function(relations) {
  ids_of_relation <- lapply(relations, function(relation) {
    names(relation$coefficients)
  })
  relation_numbers <- rep(seq_along(relations), lengths(ids_of_relation))
  list(
    ids_of_relation = ids_of_relation,
    relations_of_id = split(relation_numbers, unlist(ids_of_relation))
  )
}

# Printed non-zero counts near `small_id`, in the order they should be hidden:
# non-protected before protected, then by distance (relations reachable
# through hidden counts), then largest first.
#
# `relation_index` (from `.index_relations()`) only saves time: pass it when
# ranking many small counts against the same relations.
.rank_counts_to_hide <- function(
  report,
  small_id,
  hidden_or_unprinted_ids,
  relation_index = .index_relations(report$relations)
) {
  counts <- report$counts
  relations_seen <- integer(0)
  frontier_ids <- small_id
  visited_ids <- small_id
  layers <- list()

  while (length(frontier_ids) > 0L) {
    touches_frontier <- unique(unlist(
      relation_index$relations_of_id[frontier_ids],
      use.names = FALSE
    ))
    new_relations <- setdiff(touches_frontier, relations_seen)
    if (length(new_relations) == 0L) {
      break
    }
    relations_seen <- c(relations_seen, new_relations)
    ids_in_layer <- unique(unlist(
      relation_index$ids_of_relation[new_relations],
      use.names = FALSE
    ))
    printed_ids <- setdiff(ids_in_layer, hidden_or_unprinted_ids)
    printed_ids <- printed_ids[printed_ids %in% names(counts)]
    printed_ids <- printed_ids[
      !is.na(counts[printed_ids]) & counts[printed_ids] > 0
    ]
    layers[[length(layers) + 1L]] <- printed_ids
    frontier_ids <- setdiff(
      intersect(ids_in_layer, hidden_or_unprinted_ids),
      visited_ids
    )
    visited_ids <- c(visited_ids, frontier_ids)
  }

  largest_first <- function(ids) ids[order(-counts[ids], ids)]
  ranked_ids <- character(0)
  for (is_protected in c(FALSE, TRUE)) {
    for (layer in layers) {
      layer <- layer[(layer %in% report$protected_ids) == is_protected]
      ranked_ids <- c(ranked_ids, setdiff(largest_first(layer), ranked_ids))
    }
  }
  ranked_ids
}

# Decide which counts are hidden.
#
# Returns a list: `small_count_ids` (printed "<5"), `suppressed_ids` (printed
# "<suppr."), `uncertified_ids` (small counts that could not be protected even
# after hiding everything reachable).
.decide_which_counts_to_hide <- function(report) {
  if (!report$hide_small_counts) {
    return(list(
      small_count_ids = character(0),
      suppressed_ids = character(0),
      uncertified_ids = character(0)
    ))
  }
  counts <- report$counts
  relations <- report$relations

  small_ids <- names(counts)[
    !is.na(counts) & counts >= 1 & counts < .disclosure_threshold
  ]

  # Rule 2: hide the total of any group that contains a small count.
  suppressed_ids <- character(0)
  for (relation in relations) {
    total_id <- relation$total_id
    contains_small_count <- any(names(relation$coefficients) %in% small_ids)
    if (
      !is.null(total_id) &&
        contains_small_count &&
        !(total_id %in% report$protected_ids) &&
        !(total_id %in% small_ids)
    ) {
      suppressed_ids <- union(suppressed_ids, total_id)
    }
  }

  all_ids <- as.character(unique(c(
    names(counts),
    unlist(lapply(relations, function(relation) names(relation$coefficients)))
  )))
  unprinted_ids <- all_ids[startsWith(all_ids, "~")]
  relation_coefficients <- .index_relation_coefficients(relations, all_ids)
  upper_bound <- .count_upper_bound(report)
  relation_index <- .index_relations(relations)

  # Rule 3: keep hiding one more count until every small count is protected.
  # Hiding another count never un-protects a small count that already passed:
  # the shift that protected it only moves counts that were hidden then, and
  # they stay hidden with the same ranges. So a small count is checked until
  # it passes, not again on every pass -- which, with a thousand small counts
  # and one count hidden per pass, is what made large reports never finish.
  certified_ids <- character(0)
  repeat {
    hidden_or_unprinted_ids <- union(
      union(small_ids, suppressed_ids),
      unprinted_ids
    )
    hid_another_count <- FALSE
    uncertified_ids <- character(0)
    is_protected <- .make_small_count_checker(
      report,
      relation_coefficients,
      suppressed_ids,
      small_ids,
      unprinted_ids,
      upper_bound
    )
    for (small_id in setdiff(small_ids, certified_ids)) {
      if (is_protected(small_id)) {
        certified_ids <- c(certified_ids, small_id)
        next
      }
      candidate_ids <- .rank_counts_to_hide(
        report,
        small_id,
        hidden_or_unprinted_ids,
        relation_index
      )
      if (length(candidate_ids) == 0L) {
        uncertified_ids <- c(uncertified_ids, small_id)
        next
      }
      suppressed_ids <- union(suppressed_ids, candidate_ids[1L])
      hid_another_count <- TRUE
      break
    }
    if (!hid_another_count) {
      break
    }
  }

  list(
    small_count_ids = small_ids,
    suppressed_ids = suppressed_ids,
    uncertified_ids = uncertified_ids
  )
}


# ---- Turning counts into text ----

# How one registered count is printed, given `.decide_which_counts_to_hide()`.
.format_count <- function(report, decision, id) {
  if (id %in% decision$small_count_ids) {
    return(paste0("<", .disclosure_threshold))
  }
  if (id %in% decision$suppressed_ids) {
    return("<suppr.>")
  }
  value <- report$counts[[id]]
  if (is.na(value)) "NA" else format(value, scientific = FALSE, trim = TRUE)
}

# A function that replaces every "{{id}}" in a character vector with the
# printable form of that count. "{{pct:a,b}}" prints a / (a + b) as a
# percentage, or "-" if either count is hidden.
.make_placeholder_resolver <- function(report, decision) {
  resolve_one_string <- function(text) {
    matches <- gregexpr(.placeholder_pattern, text)
    placeholders <- regmatches(text, matches)[[1L]]
    if (length(placeholders) == 0L) {
      return(text)
    }
    replacements <- vapply(
      placeholders,
      function(placeholder) {
        id <- sub(.placeholder_pattern, "\\1", placeholder)
        if (startsWith(id, "pct:")) {
          part_ids <- strsplit(substring(id, 5L), ",", fixed = TRUE)[[1L]]
          hidden_ids <- c(decision$small_count_ids, decision$suppressed_ids)
          if (any(part_ids %in% hidden_ids)) {
            return("-")
          }
          first <- report$counts[[part_ids[1L]]]
          second <- report$counts[[part_ids[2L]]]
          return(sprintf("%.1f%%", 100 * first / (first + second)))
        }
        if (!id %in% names(report$counts)) {
          return("?")
        }
        .format_count(report, decision, id)
      },
      character(1)
    )
    regmatches(text, matches) <- list(replacements)
    text
  }
  function(text) {
    vapply(text, resolve_one_string, character(1), USE.NAMES = FALSE)
  }
}
