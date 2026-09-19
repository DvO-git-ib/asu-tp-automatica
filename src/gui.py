# gui.py
# Графическое приложение АСУ ТП «Автоматика».

import csv

import tkinter as tk
from tkinter import ttk, messagebox, simpledialog, filedialog

import config
from db_connection import get_connection, close_connection
from auth import get_current_user_info
from operators import get_current_params, get_active_alarms, confirm_alarm
from privileged_ops import get_all_params, update_parameter, get_change_log, get_parameter_history
from admin_ops import list_users, add_user, delete_user, get_positions, get_roles, set_user_active, change_user_password
from ib_ops import get_full_log
from unprivileged_ops import get_public_params
from dashboard_ops import get_dashboard_summary, get_access_matrix_rows, get_control_example_rows
from audit_ops import log_login, log_logout, get_login_log
from utils import format_datetime, format_value, bool_ru, status_ru, safe_text
from db_helpers import AppDatabaseError, NEUTRAL_ERROR, safe_rollback


APP_TITLE = config.APP_TITLE
APP_SUBTITLE = config.APP_SUBTITLE


class LoginWindow:
    def __init__(self):
        self.window = tk.Tk()
        self.window.title(APP_TITLE + " - вход")
        self.window.geometry(config.LOGIN_WINDOW_SIZE)
        self.window.resizable(False, False)
        self.status_var = tk.StringVar()
        self.status_var.set("Введите логин и пароль для входа.")
        self.failed_login_attempts = 0
        self.max_login_attempts = getattr(config, 'MAX_LOGIN_ATTEMPTS', 3)
        self.setup_style()
        self.create_widgets()

    def setup_style(self):
        style = ttk.Style()
        try:
            style.theme_use('clam')
        except Exception:
            pass

        style.configure('TFrame', background='#f3f5f7')
        style.configure('Header.TFrame', background='#263238')
        style.configure('Header.TLabel', background='#263238', foreground='white', font=('Sans', 14, 'bold'))
        style.configure('SubHeader.TLabel', background='#263238', foreground='#dce3e8', font=('Sans', 9))
        style.configure('TLabel', background='#f3f5f7', font=('Sans', 10))
        style.configure('Hint.TLabel', background='#f3f5f7', foreground='#607d8b', font=('Sans', 9))
        style.configure('TButton', font=('Sans', 10), padding=6)
        style.configure('Accent.TButton', font=('Sans', 10, 'bold'), padding=7)
        style.configure('Status.TLabel', background='#eceff1', foreground='#37474f', font=('Sans', 9))

    def create_widgets(self):
        header = ttk.Frame(self.window, style='Header.TFrame')
        header.pack(fill=tk.X)
        ttk.Label(header, text=APP_TITLE, style='Header.TLabel').pack(anchor=tk.W, padx=20, pady=(14, 2))
        ttk.Label(header, text=APP_SUBTITLE, style='SubHeader.TLabel').pack(anchor=tk.W, padx=20, pady=(0, 14))

        main = ttk.Frame(self.window, padding=22)
        main.pack(fill=tk.BOTH, expand=True)

        form = ttk.Frame(main)
        form.pack(fill=tk.X)

        ttk.Label(form, text="Логин:").grid(row=0, column=0, sticky=tk.W, pady=7)
        self.entry_login = ttk.Entry(form, width=34)
        self.entry_login.grid(row=0, column=1, sticky=tk.EW, pady=7, padx=(12, 0))

        ttk.Label(form, text="Пароль:").grid(row=1, column=0, sticky=tk.W, pady=7)
        self.entry_password = ttk.Entry(form, show="*", width=34)
        self.entry_password.grid(row=1, column=1, sticky=tk.EW, pady=7, padx=(12, 0))
        form.columnconfigure(1, weight=1)

        ttk.Button(main, text="Войти в систему", style='Accent.TButton', command=self.login).pack(fill=tk.X, pady=(20, 8))
        ttk.Label(main, text="Используйте выданную учетную запись.", style='Hint.TLabel').pack(anchor=tk.W)

        status = ttk.Label(self.window, textvariable=self.status_var, style='Status.TLabel', anchor=tk.W)
        status.pack(side=tk.BOTTOM, fill=tk.X)

        self.entry_login.focus_set()
        self.window.bind('<Return>', lambda event: self.login())

    def login(self):
        login = self.entry_login.get().strip()
        password = self.entry_password.get()

        if not login or not password:
            messagebox.showwarning("Проверка данных", "Введите логин и пароль.")
            return

        self.status_var.set("Подключение к БД...")
        self.window.update_idletasks()

        conn = get_connection(login, password)
        if not conn:
            self.register_failed_login_attempt()
            return

        try:
            info = get_current_user_info(conn)
        except AppDatabaseError:
            info = None

        if not info:
            close_connection(conn)
            self.register_failed_login_attempt(message="Не удалось определить роль пользователя.")
            return

        self.failed_login_attempts = 0

        try:
            log_login(conn)
        except Exception:
            # Ошибка аудита входа не должна блокировать запуск интерфейса.
            safe_rollback(conn)

        self.window.destroy()
        MainWindow(conn, info)

    def register_failed_login_attempt(self, message=None):
        """Обрабатывает неуспешную попытку входа.

        Лимит действует в пределах текущего окна авторизации.
        После трёх неуспешных попыток приложение закрывается.
        """
        self.failed_login_attempts += 1
        attempts_left = self.max_login_attempts - self.failed_login_attempts

        if self.failed_login_attempts >= self.max_login_attempts:
            self.status_var.set("Превышено количество попыток входа.")
            messagebox.showerror(
                "Вход заблокирован",
                "Превышено количество неуспешных попыток входа. Приложение будет закрыто."
            )
            try:
                self.window.destroy()
            except Exception:
                pass
            return

        if message is None:
            message = "Неверный логин/пароль или сервер недоступен."

        self.status_var.set(
            "Ошибка входа. Осталось попыток: {}.".format(attempts_left)
        )
        messagebox.showerror(
            "Ошибка входа",
            "{}\nОсталось попыток: {}.".format(message, attempts_left)
        )
        self.entry_password.delete(0, tk.END)
        self.entry_password.focus_set()

    def run(self):
        self.window.mainloop()


class MainWindow:
    def __init__(self, conn, user_info):
        self.conn = conn
        self.user_info = user_info or {}
        self.login = self.user_info.get('login') or ''
        self.full_name = self.user_info.get('full_name') or self.login
        self.role = self.user_info.get('role_name') or ''
        self.window = tk.Tk()
        self.window.title("{} - {} ({})".format(APP_TITLE, self.login, self.role))
        self.window.geometry(config.MAIN_WINDOW_SIZE)
        self.window.minsize(960, 620)

        self.status_var = tk.StringVar()
        self.status_var.set("Готово.")
        self.tree_registry = []
        self.user_tree = None
        self.param_tree = None
        self.alarm_tree = None
        self.positions_cache = []
        self.roles_cache = []
        self.return_to_login = False

        self.setup_style()
        self.create_menu()
        self.create_widgets()
        self.window.protocol("WM_DELETE_WINDOW", self.close_app)
        self.window.mainloop()

        if self.return_to_login:
            LoginWindow().run()

    def create_menu(self):
        menu_bar = tk.Menu(self.window)

        file_menu = tk.Menu(menu_bar, tearoff=0)
        file_menu.add_command(label="Обновить все таблицы", command=self.refresh_all_tables)
        file_menu.add_separator()
        file_menu.add_command(label="Сменить пользователя", command=self.on_exit)
        file_menu.add_command(label="Закрыть приложение", command=self.close_app)
        menu_bar.add_cascade(label="Файл", menu=file_menu)

        help_menu = tk.Menu(menu_bar, tearoff=0)
        help_menu.add_command(label="О программе", command=self.show_about)
        help_menu.add_command(label="Рекомендации по работе", command=self.show_security_note)
        menu_bar.add_cascade(label="Справка", menu=help_menu)

        self.window.config(menu=menu_bar)

    def setup_style(self):
        style = ttk.Style()
        try:
            style.theme_use('clam')
        except Exception:
            pass

        style.configure('Root.TFrame', background='#f3f5f7')
        style.configure('Top.TFrame', background='#263238')
        style.configure('TopTitle.TLabel', background='#263238', foreground='white', font=('Sans', 13, 'bold'))
        style.configure('TopInfo.TLabel', background='#263238', foreground='#dce3e8', font=('Sans', 9))
        style.configure('Section.TLabel', background='#f3f5f7', foreground='#263238', font=('Sans', 12, 'bold'))
        style.configure('Hint.TLabel', background='#f3f5f7', foreground='#607d8b', font=('Sans', 9))
        style.configure('Status.TLabel', background='#eceff1', foreground='#37474f', font=('Sans', 9))
        style.configure('TButton', font=('Sans', 9), padding=5)
        style.configure('Accent.TButton', font=('Sans', 9, 'bold'), padding=5)
        style.configure('Danger.TButton', font=('Sans', 9, 'bold'), padding=5)
        style.configure('Treeview', font=('Sans', 9), rowheight=24)
        style.configure('Treeview.Heading', font=('Sans', 9, 'bold'))
        style.configure('TNotebook.Tab', padding=(12, 6), font=('Sans', 9))

    def create_widgets(self):
        root = ttk.Frame(self.window, style='Root.TFrame')
        root.pack(fill=tk.BOTH, expand=True)

        top = ttk.Frame(root, style='Top.TFrame')
        top.pack(side=tk.TOP, fill=tk.X)

        title_frame = ttk.Frame(top, style='Top.TFrame')
        title_frame.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=18, pady=10)

        ttk.Label(title_frame, text=APP_TITLE, style='TopTitle.TLabel').pack(anchor=tk.W)
        ttk.Label(
            title_frame,
            text="{} | Пользователь: {} | Роль: {}".format(APP_SUBTITLE, self.full_name, self.role),
            style='TopInfo.TLabel'
        ).pack(anchor=tk.W, pady=(2, 0))

        button_frame = ttk.Frame(top, style='Top.TFrame')
        button_frame.pack(side=tk.RIGHT, padx=16, pady=10)
        ttk.Button(button_frame, text="Сменить пользователя", command=self.on_exit).pack(side=tk.RIGHT)

        content = ttk.Frame(root, padding=(10, 10, 10, 6))
        content.pack(fill=tk.BOTH, expand=True)

        self.notebook = ttk.Notebook(content)
        self.notebook.pack(fill=tk.BOTH, expand=True)

        self.create_role_tabs()

        status = ttk.Label(root, textvariable=self.status_var, style='Status.TLabel', anchor=tk.W)
        status.pack(side=tk.BOTTOM, fill=tk.X)

    def get_role_capabilities(self):
        mapping = {
            "Непривилегированный": [
                "просмотр общедоступных параметров",
                "отсутствие доступа к коммерческой тайне",
                "отсутствие операций изменения"
            ],
            "Оператор": [
                "просмотр технологических параметров",
                "просмотр активных аварий",
                "подтверждение аварийных событий"
            ],
            "Инженер": [
                "просмотр всех технологических параметров",
                "изменение технологических параметров",
                "просмотр журнала изменений"
            ],
            "Привилегированный": [
                "расширенный просмотр технологических параметров",
                "изменение технологических параметров",
                "контроль изменений через журнал"
            ],
            "Администратор ИС": [
                "просмотр учетных записей",
                "добавление и обновление пользователей",
                "управление состоянием учетных записей"
            ],
            "Администратор ИБ": [
                "просмотр полного журнала операций",
                "контроль входов и завершения сеансов",
                "просмотр учетных записей"
            ]
        }
        return mapping.get(self.role, ["нет доступных операций для текущей роли"])

    def create_dashboard_tab(self):
        frame = ttk.Frame(self.notebook, padding=14)
        self.notebook.add(frame, text="Главная")

        top_row = ttk.Frame(frame)
        top_row.pack(fill=tk.X, pady=(0, 10))

        left = ttk.LabelFrame(top_row, text="Пользователь и подключение", padding=10)
        left.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 8))

        rows = [
            ("ФИО", self.full_name),
            ("Логин БД", self.login),
            ("Роль", self.role),
            ("Сервер БД", "{}:{} / {}".format(config.DB_HOST, config.DB_PORT, config.DB_NAME)),
            ("Версия приложения", getattr(config, 'APP_VERSION', '3.2'))
        ]
        for i, item in enumerate(rows):
            label_text, value_text = item
            ttk.Label(left, text=label_text + ":").grid(row=i, column=0, sticky=tk.W, padx=(0, 12), pady=3)
            ttk.Label(left, text=value_text, style='Hint.TLabel').grid(row=i, column=1, sticky=tk.W, pady=3)

        right = ttk.LabelFrame(top_row, text="Информация о системе", padding=10)
        right.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(8, 0))
        security_text = (
            "Рабочее место предназначено для контроля параметров, аварийных событий, "
            "учетных записей и журналов системы. Доступные разделы зависят от роли "
            "пользователя. События работы приложения фиксируются в журнале."
        )
        msg = tk.Message(right, text=security_text, width=520, background='#f3f5f7', font=('Sans', 10))
        msg.pack(anchor=tk.W, fill=tk.X)

        ttk.Label(frame, text="Сводная панель", style='Section.TLabel').pack(anchor=tk.W, pady=(10, 6))
        self.create_table(
            frame,
            columns=("Показатель", "Значение", "Пояснение"),
            widths=(230, 110, 720),
            load_function=self.load_dashboard_summary,
            hint="Сводные показатели по доступным разделам системы.",
            tag_function=self.tag_dashboard_row
        )

    def load_dashboard_summary(self):
        rows = get_dashboard_summary(self.conn, self.role)
        result = []
        for r in rows:
            result.append((r[0], r[1], r[2]))
        return result

    def tag_dashboard_row(self, values):
        if len(values) >= 1 and values[0] == "Активные аварии":
            try:
                if int(values[1]) > 0:
                    return 'warning'
            except Exception:
                pass
        return ''

    def create_access_matrix_tab(self):
        frame = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Матрица доступа")
        self.create_table(
            frame,
            columns=("Роль", "Разрешение", "Описание"),
            widths=(190, 220, 720),
            load_function=self.load_access_matrix,
            hint="Справочник рабочих полномочий по ролям.",
            tag_function=self.tag_access_matrix_row
        )

    def load_access_matrix(self):
        return get_access_matrix_rows(self.conn)

    def tag_access_matrix_row(self, values):
        if values and values[0] == self.role:
            return 'current'
        return ''

    def create_control_example_tab(self):
        frame = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Проверка доступа")
        self.create_table(
            frame,
            columns=("№", "Операция", "Кому разрешено", "Как реализовано"),
            widths=(60, 260, 320, 520),
            load_function=self.load_control_example,
            hint="Справочная информация по доступным операциям.",
            tag_function=self.tag_control_example_row
        )

    def load_control_example(self):
        return get_control_example_rows(self.role)

    def tag_control_example_row(self, values):
        if len(values) >= 3 and "Никто" in values[2]:
            return 'danger'
        if len(values) >= 3 and self.role in values[2]:
            return 'current'
        return ''

    def create_role_tabs(self):
        self.create_dashboard_tab()
        self.create_access_matrix_tab()
        if self.role == "Непривилегированный":
            self.create_unprivileged_tabs()
        elif self.role == "Оператор":
            self.create_operator_tabs()
        elif self.role in ("Инженер", "Привилегированный"):
            self.create_engineer_tabs()
        elif self.role == "Администратор ИС":
            self.create_admin_tabs()
        elif self.role == "Администратор ИБ":
            self.create_ib_tabs()
        else:
            frame = ttk.Frame(self.notebook, padding=20)
            self.notebook.add(frame, text="Доступ")
            ttk.Label(frame, text="Для вашей роли нет доступных разделов.", style='Section.TLabel').pack(anchor=tk.W)

    # ------------------------------------------------------------------
    # Непривилегированный пользователь
    # ------------------------------------------------------------------
    def create_unprivileged_tabs(self):
        frame = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(frame, text="Общедоступные параметры")
        self.create_table(
            frame,
            columns=("Название", "Значение", "Ед. изм.", "Расположение"),
            widths=(300, 130, 90, 440),
            load_function=self.load_public_params,
            hint="Параметры общего мониторинга."
        )

    def load_public_params(self):
        rows = get_public_params(self.conn)
        result = []
        for r in rows:
            result.append((r[0], format_value(r[1], r[2]), r[2] or "", r[3] or ""))
        return result

    # ------------------------------------------------------------------
    # Оператор
    # ------------------------------------------------------------------
    def create_operator_tabs(self):
        tab_params = ttk.Frame(self.notebook, padding=8)
        tab_alarms = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab_params, text="Параметры")
        self.notebook.add(tab_alarms, text="Аварии")

        self.create_table(
            tab_params,
            columns=("Название", "Значение", "Ед. изм.", "Расположение"),
            widths=(300, 130, 90, 440),
            load_function=self.load_current_params,
            hint="Оператор видит рабочие параметры технологического процесса."
        )

        buttons = [
            ("Подтвердить выбранную аварию", self.do_confirm_alarm)
        ]
        self.alarm_tree = self.create_table(
            tab_alarms,
            columns=("ID", "Объект", "Уровень", "Дата", "Описание"),
            widths=(70, 220, 80, 160, 560),
            load_function=self.load_alarms,
            hint="Журнал активных аварийных событий.",
            buttons=buttons,
            tag_function=self.tag_alarm_row
        )

    def load_current_params(self):
        rows = get_current_params(self.conn)
        result = []
        for r in rows:
            result.append((r[0], format_value(r[1], r[2]), r[2] or "", r[3] or ""))
        return result

    def load_alarms(self):
        rows = get_active_alarms(self.conn, 50)
        result = []
        for r in rows:
            result.append((r[0], r[3] or "", r[4] or "", format_datetime(r[2]), safe_text(r[1], 120)))
        return result

    def tag_alarm_row(self, values):
        try:
            severity = int(values[2])
        except Exception:
            severity = 0
        if severity >= 5:
            return 'critical'
        if severity >= 4:
            return 'danger'
        if severity >= 3:
            return 'warning'
        return ''

    def do_confirm_alarm(self):
        if not self.alarm_tree:
            return
        values = self.get_selected_values(self.alarm_tree)
        if not values:
            messagebox.showinfo("Выбор аварии", "Выберите аварию в таблице.")
            return
        alarm_id = values[0]
        if not messagebox.askyesno("Подтверждение", "Подтвердить аварию ID {}?".format(alarm_id)):
            return
        try:
            success, message = confirm_alarm(self.conn, int(alarm_id))
            if success:
                messagebox.showinfo("Выполнено", message)
                self.refresh_tree(self.alarm_tree, self.load_alarms)
            else:
                messagebox.showwarning("Операция не выполнена", message)
        except Exception as e:
            self.handle_error(e)

    # ------------------------------------------------------------------
    # Инженер / привилегированный пользователь
    # ------------------------------------------------------------------
    def create_engineer_tabs(self):
        tab_params = ttk.Frame(self.notebook, padding=8)
        tab_log = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab_params, text="Технологические параметры")
        self.notebook.add(tab_log, text="Журнал изменений")

        buttons = [
            ("Изменить выбранный параметр", self.do_update_selected_parameter),
            ("История параметра", self.do_show_parameter_history)
        ]
        self.param_tree = self.create_table(
            tab_params,
            columns=("ID", "Название", "Значение", "Ед. изм.", "Расположение", "Коммерч. тайна"),
            widths=(60, 270, 120, 80, 360, 130),
            load_function=self.load_all_params,
            hint="Выберите параметр для изменения или просмотра истории.",
            buttons=buttons,
            tag_function=self.tag_secret_row
        )

        self.create_table(
            tab_log,
            columns=("Дата", "Статус", "Описание"),
            widths=(170, 100, 760),
            load_function=self.load_change_log,
            hint="Последние изменения технологических параметров.",
            tag_function=self.tag_success_row
        )

    def load_all_params(self):
        rows = get_all_params(self.conn)
        result = []
        for r in rows:
            result.append((r[0], r[1], format_value(r[2], r[3]), r[3] or "", r[4] or "", bool_ru(r[5])))
        return result

    def load_change_log(self):
        rows = get_change_log(self.conn, 100)
        result = []
        for r in rows:
            result.append((format_datetime(r[1]), status_ru(r[2]), safe_text(r[0], 160)))
        return result

    def tag_secret_row(self, values):
        if len(values) >= 6 and values[5] == "Да":
            return 'secret'
        return ''

    def tag_success_row(self, values):
        if len(values) >= 2 and values[1] == "Ошибка":
            return 'danger'
        return ''

    def do_update_selected_parameter(self):
        if not self.param_tree:
            return
        values = self.get_selected_values(self.param_tree)
        if not values:
            messagebox.showinfo("Выбор параметра", "Выберите параметр в таблице.")
            return
        object_id = values[0]
        object_name = values[1]
        new_value = simpledialog.askfloat(
            "Изменение параметра",
            "Введите новое значение для параметра:\n{}".format(object_name),
            parent=self.window
        )
        if new_value is None:
            return
        try:
            success, message = update_parameter(self.conn, int(object_id), float(new_value))
            if success:
                messagebox.showinfo("Выполнено", message)
                self.refresh_tree(self.param_tree, self.load_all_params)
            else:
                messagebox.showwarning("Операция не выполнена", message)
        except Exception as e:
            self.handle_error(e)

    def do_show_parameter_history(self):
        if not self.param_tree:
            return
        values = self.get_selected_values(self.param_tree)
        if not values:
            messagebox.showinfo("История параметра", "Выберите параметр в таблице.")
            return

        object_id = values[0]
        object_name = values[1]

        try:
            rows = get_parameter_history(self.conn, int(object_id), 100)
        except Exception as e:
            self.handle_error(e)
            return

        result = []
        for r in rows:
            result.append((
                format_datetime(r[0]),
                r[1] or "",
                format_value(r[2]),
                format_value(r[3]),
                status_ru(r[4]),
                safe_text(r[5], 160)
            ))

        self.show_rows_window(
            "История параметра",
            "История изменения параметра: {}".format(object_name),
            ("Дата", "Пользователь БД", "Старое значение", "Новое значение", "Статус", "Описание"),
            (160, 140, 120, 120, 90, 500),
            result
        )

    # ------------------------------------------------------------------
    # Администратор ИС
    # ------------------------------------------------------------------
    def create_admin_tabs(self):
        tab_users = ttk.Frame(self.notebook, padding=8)
        tab_add = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(tab_users, text="Пользователи")
        self.notebook.add(tab_add, text="Добавить / обновить")

        buttons = [
            ("Заблокировать", self.do_block_selected_user),
            ("Разблокировать", self.do_unblock_selected_user),
            ("Сменить пароль", self.do_change_selected_user_password)
        ]
        self.user_tree = self.create_table(
            tab_users,
            columns=("ID", "ФИО", "Логин", "Должность", "Роль", "Активен", "Создан"),
            widths=(60, 230, 120, 210, 160, 80, 150),
            load_function=self.load_users,
            hint="Список учетных записей и их текущий статус.",
            buttons=buttons,
            tag_function=self.tag_user_row
        )

        self.create_add_user_form(tab_add)

    def load_users(self):
        rows = list_users(self.conn)
        result = []
        for r in rows:
            result.append((r[0], r[1], r[2], r[3] or "", r[4] or "", bool_ru(r[5]), format_datetime(r[6])))
        return result

    def tag_user_row(self, values):
        if len(values) >= 6 and values[5] == "Нет":
            return 'inactive'
        return ''

    def create_add_user_form(self, parent):
        ttk.Label(parent, text="Добавление или обновление пользователя", style='Section.TLabel').pack(anchor=tk.W, pady=(0, 4))
        ttk.Label(parent, text="Заполните карточку пользователя и сохраните изменения.", style='Hint.TLabel').pack(anchor=tk.W, pady=(0, 12))

        try:
            self.positions_cache = get_positions(self.conn)
        except Exception:
            self.positions_cache = []
        try:
            self.roles_cache = get_roles(self.conn)
        except Exception:
            self.roles_cache = []

        form = ttk.Frame(parent)
        form.pack(anchor=tk.NW, fill=tk.X)

        self.add_full_name = ttk.Entry(form, width=44)
        self.add_login = ttk.Entry(form, width=44)
        self.add_password = ttk.Entry(form, show="*", width=44)
        self.add_position = ttk.Combobox(form, values=self.positions_cache, state='readonly', width=42)
        self.add_role = ttk.Combobox(form, values=self.roles_cache, state='readonly', width=42)
        self.add_active = tk.BooleanVar()
        self.add_active.set(True)

        rows = [
            ("ФИО:", self.add_full_name),
            ("Логин:", self.add_login),
            ("Пароль:", self.add_password),
            ("Должность:", self.add_position),
            ("Роль:", self.add_role)
        ]

        for i, item in enumerate(rows):
            label_text, widget = item
            ttk.Label(form, text=label_text).grid(row=i, column=0, sticky=tk.W, padx=(0, 14), pady=6)
            widget.grid(row=i, column=1, sticky=tk.W, pady=6)

        ttk.Checkbutton(form, text="Учетная запись активна", variable=self.add_active).grid(row=5, column=1, sticky=tk.W, pady=8)

        if self.positions_cache:
            self.add_position.current(0)
        if self.roles_cache:
            self.add_role.current(0)

        button_row = ttk.Frame(parent)
        button_row.pack(anchor=tk.W, pady=(14, 0))
        ttk.Button(button_row, text="Сохранить пользователя", style='Accent.TButton', command=self.do_add_user).pack(side=tk.LEFT)
        ttk.Button(button_row, text="Очистить форму", command=self.clear_add_user_form).pack(side=tk.LEFT, padx=(8, 0))

    def clear_add_user_form(self):
        for widget in (self.add_full_name, self.add_login, self.add_password):
            widget.delete(0, tk.END)
        if self.positions_cache:
            self.add_position.current(0)
        if self.roles_cache:
            self.add_role.current(0)
        self.add_active.set(True)

    def do_add_user(self):
        full_name = self.add_full_name.get().strip()
        login = self.add_login.get().strip()
        password = self.add_password.get()
        position = self.add_position.get().strip()
        role = self.add_role.get().strip()
        active = bool(self.add_active.get())

        if not full_name or not login or not password or not position or not role:
            messagebox.showwarning("Проверка данных", "Заполните все поля формы.")
            return
        if len(password) < 8:
            messagebox.showwarning("Проверка данных", "Пароль должен содержать не менее 8 символов.")
            return

        try:
            success, message = add_user(self.conn, full_name, login, password, position, role, active)
            if success:
                messagebox.showinfo("Выполнено", message)
                self.clear_add_user_form()
                if self.user_tree:
                    self.refresh_tree(self.user_tree, self.load_users)
            else:
                messagebox.showwarning("Операция не выполнена", message)
        except Exception as e:
            self.handle_error(e)

    def do_block_selected_user(self):
        if not self.user_tree:
            return
        values = self.get_selected_values(self.user_tree)
        if not values:
            messagebox.showinfo("Выбор пользователя", "Выберите пользователя в таблице.")
            return
        user_id = values[0]
        login = values[2]
        if not messagebox.askyesno("Блокировка", "Заблокировать пользователя {}?".format(login)):
            return
        try:
            success, message = delete_user(self.conn, int(user_id))
            if success:
                messagebox.showinfo("Выполнено", message)
                self.refresh_tree(self.user_tree, self.load_users)
            else:
                messagebox.showwarning("Операция не выполнена", message)
        except Exception as e:
            self.handle_error(e)

    def do_unblock_selected_user(self):
        if not self.user_tree:
            return
        values = self.get_selected_values(self.user_tree)
        if not values:
            messagebox.showinfo("Выбор пользователя", "Выберите пользователя в таблице.")
            return
        user_id = values[0]
        login = values[2]
        if not messagebox.askyesno("Разблокировка", "Разблокировать пользователя {}?".format(login)):
            return
        try:
            success, message = set_user_active(self.conn, int(user_id), True)
            if success:
                messagebox.showinfo("Выполнено", message)
                self.refresh_tree(self.user_tree, self.load_users)
            else:
                messagebox.showwarning("Операция не выполнена", message)
        except Exception as e:
            self.handle_error(e)

    def do_change_selected_user_password(self):
        if not self.user_tree:
            return
        values = self.get_selected_values(self.user_tree)
        if not values:
            messagebox.showinfo("Выбор пользователя", "Выберите пользователя в таблице.")
            return
        user_id = values[0]
        login = values[2]
        new_password = simpledialog.askstring(
            "Смена пароля",
            "Введите новый пароль для пользователя {}:".format(login),
            show="*",
            parent=self.window
        )
        if new_password is None:
            return
        if len(new_password) < 8:
            messagebox.showwarning("Проверка данных", "Пароль должен содержать не менее 8 символов.")
            return
        repeat_password = simpledialog.askstring(
            "Смена пароля",
            "Повторите новый пароль:",
            show="*",
            parent=self.window
        )
        if repeat_password is None:
            return
        if new_password != repeat_password:
            messagebox.showwarning("Проверка данных", "Пароли не совпадают.")
            return
        if not messagebox.askyesno("Смена пароля", "Сменить пароль пользователю {}?".format(login)):
            return
        try:
            success, message = change_user_password(self.conn, int(user_id), new_password)
            if success:
                messagebox.showinfo("Выполнено", message)
                self.refresh_tree(self.user_tree, self.load_users)
            else:
                messagebox.showwarning("Операция не выполнена", message)
        except Exception as e:
            self.handle_error(e)

    # ------------------------------------------------------------------
    # Администратор ИБ
    # ------------------------------------------------------------------
    def create_ib_tabs(self):
        tab_access = ttk.Frame(self.notebook, padding=8)
        tab_login = ttk.Frame(self.notebook, padding=8)
        tab_users = ttk.Frame(self.notebook, padding=8)
        self.notebook.add(tab_access, text="Журнал операций")
        self.notebook.add(tab_login, text="Входы/выходы")
        self.notebook.add(tab_users, text="Пользователи")

        self.create_table(
            tab_access,
            columns=("ID", "DB пользователь", "Событие", "Действие", "Объект", "IP", "Дата", "Успех", "Описание"),
            widths=(60, 130, 150, 130, 80, 120, 160, 70, 420),
            load_function=self.load_full_log,
            hint="Журнал событий системы.",
            tag_function=self.tag_log_row
        )

        self.create_table(
            tab_login,
            columns=("ID", "Пользователь БД", "Действие", "Дата", "Успех", "Описание"),
            widths=(70, 160, 110, 170, 80, 620),
            load_function=self.load_login_log,
            hint="Входы и завершения сеансов пользователей.",
            tag_function=self.tag_login_log_row
        )


        self.create_table(
            tab_users,
            columns=("ID", "ФИО", "Логин", "Должность", "Роль", "Активен", "Создан"),
            widths=(60, 230, 120, 210, 160, 80, 150),
            load_function=self.load_users,
            hint="Просмотр учетных записей.",
            tag_function=self.tag_user_row
        )


    def load_full_log(self):
        rows = get_full_log(self.conn, 200)
        result = []
        for r in rows:
            # f_get_logs: log_id, db_user, event_type, action_name, object_id,
            # ip_address, action_date, success, description, error_message
            result.append((
                r[0],
                r[1] or "",
                r[2] or "",
                r[3] or "",
                r[4] or "",
                r[5] or "",
                format_datetime(r[6]),
                status_ru(r[7]),
                safe_text(r[8], 180)
            ))
        return result

    def load_login_log(self):
        rows = get_login_log(self.conn, 200)
        result = []
        for r in rows:
            result.append((
                r[0],
                r[1] or "",
                r[2] or "",
                format_datetime(r[3]),
                status_ru(r[4]),
                safe_text(r[5], 180)
            ))
        return result

    def tag_login_log_row(self, values):
        if len(values) >= 3 and values[2] == "LOGOUT":
            return 'inactive'
        if len(values) >= 5 and values[4] == "Ошибка":
            return 'danger'
        return ''


    def tag_log_row(self, values):
        if len(values) >= 7 and values[6] == "Ошибка":
            return 'danger'
        return ''

    # ------------------------------------------------------------------
    # Общие методы таблиц и обработки ошибок
    # ------------------------------------------------------------------
    def create_table(self, parent, columns, widths, load_function, hint=None, buttons=None, tag_function=None):
        if hint:
            ttk.Label(parent, text=hint, style='Hint.TLabel').pack(anchor=tk.W, pady=(0, 6))

        toolbar = ttk.Frame(parent)
        toolbar.pack(fill=tk.X, pady=(0, 6))

        filter_var = tk.StringVar()
        ttk.Label(toolbar, text="Фильтр:").pack(side=tk.LEFT, padx=(0, 5))
        filter_entry = ttk.Entry(toolbar, textvariable=filter_var, width=24)
        filter_entry.pack(side=tk.LEFT, padx=(0, 8))

        table_frame = ttk.Frame(parent)
        table_frame.pack(fill=tk.BOTH, expand=True)

        tree = ttk.Treeview(table_frame, columns=columns, show='headings', selectmode='browse')
        for i, col in enumerate(columns):
            width = widths[i] if i < len(widths) else 120
            tree.heading(col, text=col)
            tree.column(col, width=width, anchor=tk.W, stretch=True)

        y_scroll = ttk.Scrollbar(table_frame, orient=tk.VERTICAL, command=tree.yview)
        x_scroll = ttk.Scrollbar(table_frame, orient=tk.HORIZONTAL, command=tree.xview)
        tree.configure(yscrollcommand=y_scroll.set, xscrollcommand=x_scroll.set)

        tree.grid(row=0, column=0, sticky='nsew')
        y_scroll.grid(row=0, column=1, sticky='ns')
        x_scroll.grid(row=1, column=0, sticky='ew')
        table_frame.rowconfigure(0, weight=1)
        table_frame.columnconfigure(0, weight=1)

        tree.tag_configure('danger', background='#ffcdd2')
        tree.tag_configure('critical', background='#ef9a9a')
        tree.tag_configure('warning', background='#fff9c4')
        tree.tag_configure('secret', background='#e1f5fe')
        tree.tag_configure('inactive', background='#eeeeee')
        tree.tag_configure('current', background='#c8e6c9')

        ttk.Button(toolbar, text="Обновить", command=lambda: self.refresh_tree(tree, load_function, tag_function, filter_var)).pack(side=tk.LEFT)
        ttk.Button(toolbar, text="Применить фильтр", command=lambda: self.refresh_tree(tree, load_function, tag_function, filter_var)).pack(side=tk.LEFT, padx=(8, 0))
        ttk.Button(toolbar, text="Сбросить", command=lambda: self.clear_filter_and_refresh(filter_var, tree, load_function, tag_function)).pack(side=tk.LEFT, padx=(8, 0))

        if buttons:
            for item in buttons:
                text, command = item
                ttk.Button(toolbar, text=text, command=command).pack(side=tk.LEFT, padx=(8, 0))

        ttk.Button(toolbar, text="Экспорт CSV", command=lambda: self.export_tree_to_csv(tree, columns)).pack(side=tk.RIGHT)
        ttk.Button(toolbar, text="Карточка", command=lambda: self.show_tree_row_card(tree, columns)).pack(side=tk.RIGHT, padx=(8, 0))

        tree.bind('<Double-1>', lambda event: self.show_tree_row_card(tree, columns))
        filter_entry.bind('<Return>', lambda event: self.refresh_tree(tree, load_function, tag_function, filter_var))

        self.tree_registry.append((tree, load_function, tag_function, filter_var))
        self.refresh_tree(tree, load_function, tag_function, filter_var)
        return tree

    def refresh_tree(self, tree, load_function, tag_function=None, filter_var=None):
        try:
            self.window.config(cursor='watch')
            self.window.update_idletasks()

            for row in tree.get_children():
                tree.delete(row)

            data = load_function()
            query = ''
            if filter_var is not None:
                query = (filter_var.get() or '').strip().lower()

            shown = 0
            for item in data:
                if query:
                    haystack = ' '.join([str(value).lower() for value in item])
                    if query not in haystack:
                        continue

                tag = ''
                if tag_function:
                    try:
                        tag = tag_function(item)
                    except Exception:
                        tag = ''
                if tag:
                    tree.insert('', tk.END, values=item, tags=(tag,))
                else:
                    tree.insert('', tk.END, values=item)
                shown += 1

            if query:
                self.set_status("Данные обновлены. Отобрано: {} из {}.".format(shown, len(data)))
            else:
                self.set_status("Данные обновлены. Записей: {}.".format(shown))
        except Exception as e:
            self.handle_error(e)
        finally:
            try:
                self.window.config(cursor='')
            except Exception:
                pass

    def clear_filter_and_refresh(self, filter_var, tree, load_function, tag_function=None):
        try:
            filter_var.set('')
        except Exception:
            pass
        self.refresh_tree(tree, load_function, tag_function, filter_var)

    def refresh_all_tables(self):
        count = 0
        for item in list(self.tree_registry):
            try:
                tree, load_function, tag_function, filter_var = item
            except ValueError:
                tree, load_function, tag_function = item
                filter_var = None
            self.refresh_tree(tree, load_function, tag_function, filter_var)
            count += 1
        self.set_status("Обновлено таблиц: {}.".format(count))

    def show_rows_window(self, title, header_text, columns, widths, rows):
        win = tk.Toplevel(self.window)
        win.title(title)
        win.geometry("980x520")
        win.transient(self.window)
        win.grab_set()

        frame = ttk.Frame(win, padding=10)
        frame.pack(fill=tk.BOTH, expand=True)

        ttk.Label(frame, text=header_text, style='Section.TLabel').pack(anchor=tk.W, pady=(0, 8))

        table_frame = ttk.Frame(frame)
        table_frame.pack(fill=tk.BOTH, expand=True)

        tree = ttk.Treeview(table_frame, columns=columns, show='headings', selectmode='browse')
        for i, col in enumerate(columns):
            width = widths[i] if i < len(widths) else 120
            tree.heading(col, text=col)
            tree.column(col, width=width, anchor=tk.W, stretch=True)

        y_scroll = ttk.Scrollbar(table_frame, orient=tk.VERTICAL, command=tree.yview)
        x_scroll = ttk.Scrollbar(table_frame, orient=tk.HORIZONTAL, command=tree.xview)
        tree.configure(yscrollcommand=y_scroll.set, xscrollcommand=x_scroll.set)
        tree.grid(row=0, column=0, sticky='nsew')
        y_scroll.grid(row=0, column=1, sticky='ns')
        x_scroll.grid(row=1, column=0, sticky='ew')
        table_frame.rowconfigure(0, weight=1)
        table_frame.columnconfigure(0, weight=1)

        tree.tag_configure('danger', background='#ffcdd2')
        for row in rows:
            tag = ''
            if len(row) >= 5 and row[4] == "Ошибка":
                tag = 'danger'
            if tag:
                tree.insert('', tk.END, values=row, tags=(tag,))
            else:
                tree.insert('', tk.END, values=row)

        bottom = ttk.Frame(frame)
        bottom.pack(fill=tk.X, pady=(10, 0))
        ttk.Label(bottom, text="Записей: {}".format(len(rows)), style='Hint.TLabel').pack(side=tk.LEFT)
        ttk.Button(bottom, text="Закрыть", command=win.destroy).pack(side=tk.RIGHT)

    def show_tree_row_card(self, tree, columns):
        values = self.get_selected_values(tree)
        if not values:
            messagebox.showinfo("Карточка записи", "Выберите строку в таблице.")
            return

        lines = []
        for i, col in enumerate(columns):
            value = values[i] if i < len(values) else ""
            lines.append("{}: {}".format(col, value))

        messagebox.showinfo("Карточка записи", "\n".join(lines))

    def export_tree_to_csv(self, tree, columns):
        rows = []
        for item_id in tree.get_children():
            rows.append(tree.item(item_id, 'values'))

        if not rows:
            messagebox.showinfo("Экспорт", "В таблице нет данных для экспорта.")
            return

        filename = filedialog.asksaveasfilename(
            title="Сохранить CSV",
            defaultextension=".csv",
            filetypes=(("CSV файлы", "*.csv"), ("Все файлы", "*.*"))
        )
        if not filename:
            return

        try:
            with open(filename, 'w', newline='', encoding='utf-8-sig') as f:
                writer = csv.writer(f, delimiter=';')
                writer.writerow(columns)
                for row in rows:
                    writer.writerow(row)
            self.set_status("Экспорт выполнен: {}".format(filename))
            messagebox.showinfo("Экспорт", "Данные сохранены в CSV-файл.")
        except TypeError:
            # Совместимость с окружениями, где open(..., encoding=...) может быть ограничен.
            try:
                import codecs
                with codecs.open(filename, 'w', encoding='utf-8-sig') as f:
                    writer = csv.writer(f, delimiter=';')
                    writer.writerow(columns)
                    for row in rows:
                        writer.writerow(row)
                self.set_status("Экспорт выполнен: {}".format(filename))
                messagebox.showinfo("Экспорт", "Данные сохранены в CSV-файл.")
            except Exception as e:
                self.handle_error(e)
        except Exception as e:
            self.handle_error(e)

    def show_about(self):
        text = (
            "{}\n"
            "Версия: {}\n\n"
            "Назначение: клиентское приложение подсистемы администрирования и контроля "
            "АСУ ТП для производства железобетонных конструкций.\n\n"
            "Среда: Astra Linux «Орел» 1.7.5, Python 3.5.3, PostgreSQL 9.6.\n"
            "Подключение к базе данных выполняется по учетной записи пользователя.\n"
            "Доступные разделы определяются назначенной ролью.\n\n"
            "Дополнительно: история параметров, смена пароля, разблокировка пользователей, "
            "журнал входов и выходов."
        ).format(APP_TITLE, getattr(config, 'APP_VERSION', '3.0'))
        messagebox.showinfo("О программе", text)

    def show_security_note(self):
        text = (
            "Рекомендации по работе:\n\n"
            "1. Не передавайте учетные данные другим пользователям.\n"
            "2. Завершайте сеанс при передаче рабочего места другому пользователю.\n"
            "3. Проверяйте выбранные записи перед выполнением операций.\n"
            "4. При появлении повторяющихся ошибок обратитесь к администратору ИБ.\n"
            "5. Регулярно обновляйте данные на рабочих вкладках."
        )
        messagebox.showinfo("Рекомендации по работе", text)

    def get_selected_values(self, tree):
        selection = tree.selection()
        if not selection:
            return None
        return tree.item(selection[0], 'values')

    def set_status(self, text):
        if hasattr(self, 'status_var'):
            self.status_var.set(text)

    def handle_error(self, e):
        safe_rollback(self.conn)
        self.set_status("Ошибка выполнения операции.")

        if isinstance(e, AppDatabaseError):
            msg = e.user_message or NEUTRAL_ERROR
            details = e.technical_message
        else:
            msg = NEUTRAL_ERROR
            details = str(e)

        # Технические сведения выводятся только в режиме отладки или для администратора ИБ.
        if getattr(config, 'DEBUG_MODE', False) or self.role == "Администратор ИБ":
            if details:
                msg = msg + "\n\nТехнические сведения:\n" + safe_text(details, 700)

        messagebox.showerror("Ошибка", msg)

    def on_exit(self):
        """Выход из текущей учетной записи без закрытия приложения."""
        if not messagebox.askyesno("Смена пользователя", "Выйти из текущей учетной записи и вернуться на экран входа?"):
            return
        self.return_to_login = True
        try:
            try:
                log_logout(self.conn)
            except Exception:
                safe_rollback(self.conn)
            close_connection(self.conn)
        finally:
            self.window.destroy()

    def close_app(self):
        """Полное закрытие приложения."""
        if not messagebox.askyesno("Закрытие", "Закрыть приложение?"):
            return
        self.return_to_login = False
        try:
            try:
                log_logout(self.conn)
            except Exception:
                safe_rollback(self.conn)
            close_connection(self.conn)
        finally:
            self.window.destroy()


if __name__ == "__main__":
    app = LoginWindow()
    app.run()
