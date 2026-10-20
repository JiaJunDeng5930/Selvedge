import ./CONTRACT.bend as Rule

def Rule.submitted_search_uses_shared_bounded_query(query, project, work, prior, after, world): {==}
def Rule.editing_keyword_discards_previous_result(next, query, project, work, prior): {==}
def Rule.choosing_project_keeps_work_and_discards_previous_result(value, query, project, work, prior): {==}
def Rule.choosing_work_keeps_project_and_discards_previous_result(value, query, project, work, prior): {==}
