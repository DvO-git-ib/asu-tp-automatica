# privileged_ops.py
from db_helpers import fetch_all, execute_status_function


def get_all_params(conn):
    """Все доступные технологические параметры через функцию БД."""
    return fetch_all(
        conn,
        "SELECT object_id, object_name, current_value, unit, location, is_commercial_secret FROM asu_schema.f_get_all_params()"
    )


def update_parameter(conn, object_id, new_value):
    """Изменение параметра через функцию PostgreSQL 9.6."""
    return execute_status_function(
        conn,
        "SELECT success, message FROM asu_schema.sp_update_parameter(%s, %s)",
        (object_id, new_value)
    )


def get_change_log(conn, limit=50):
    """Журнал изменений через функцию БД."""
    return fetch_all(
        conn,
        "SELECT description, action_date, success FROM asu_schema.f_get_change_log(%s)",
        (limit,)
    )


def get_parameter_history(conn, object_id, limit=100):
    """История изменений выбранного технологического параметра."""
    return fetch_all(
        conn,
        "SELECT action_date, db_user, old_value, new_value, success, description FROM asu_schema.f_get_parameter_history(%s, %s)",
        (object_id, limit)
    )
