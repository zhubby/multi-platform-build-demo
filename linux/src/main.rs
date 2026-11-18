//! [INPUT]: 使用 GTK4 控件、tasknotes 会话与 JSON 协议。
//! [OUTPUT]: 提供任务和笔记的原生桌面界面。
//! [POS]: 应用入口；草稿驻留控件，刷新只替换列表。
//! [PROTOCOL]: Update this header on change, then check AGENTS.md
use gtk::{gio, prelude::*};
use std::{
    cell::{Cell, RefCell},
    rc::Rc,
};
use tasknotes::{address_matches, data_root, normalize_url, valid_title, Session};

struct Ui {
    window: gtk::ApplicationWindow,
    address: gtk::Entry,
    token: gtk::PasswordEntry,
    kind: gtk::DropDown,
    filter: gtk::DropDown,
    search: gtk::SearchEntry,
    list: gtk::ListBox,
    title: gtk::Entry,
    body: gtk::TextView,
    completed: gtk::CheckButton,
    status: gtk::Label,
    save: gtk::Button,
    delete: gtk::Button,
    acknowledge: gtk::Button,
    session: RefCell<Session>,
    selected: RefCell<Option<(String, u64)>>,
    visible: RefCell<Vec<(String, u64)>>,
    busy: Cell<bool>,
}
impl Ui {
    fn note(&self) -> bool {
        self.kind.selected() == 1
    }
    fn paint(&self) {
        while let Some(child) = self.list.first_child() {
            self.list.remove(&child);
        }
        let state = self.session.borrow();
        let query = self.search.text().to_lowercase();
        let filter = self.filter.selected();
        let mut visible = self.visible.borrow_mut();
        visible.clear();
        if self.note() {
            for item in &state.snapshot.notes {
                if !format!("{} {}", item.title, item.body)
                    .to_lowercase()
                    .contains(&query)
                {
                    continue;
                }
                self.list.append(
                    &gtk::Label::builder()
                        .label(&item.title)
                        .xalign(0.0)
                        .margin_top(10)
                        .margin_bottom(10)
                        .build(),
                );
                visible.push((item.id.clone(), item.revision));
            }
        } else {
            for item in &state.snapshot.tasks {
                if !item.title.to_lowercase().contains(&query)
                    || (filter == 1 && item.completed)
                    || (filter == 2 && !item.completed)
                {
                    continue;
                }
                self.list.append(
                    &gtk::Label::builder()
                        .label(format!(
                            "{}  {}",
                            if item.completed { "☑" } else { "☐" },
                            item.title
                        ))
                        .xalign(0.0)
                        .margin_top(10)
                        .margin_bottom(10)
                        .build(),
                );
                visible.push((item.id.clone(), item.revision));
            }
        }
        if visible.is_empty() {
            self.list
                .append(&gtk::Label::new(Some("暂无匹配记录。点击“新建”开始。")));
        }
        self.title.set_editable(state.online);
        self.body.set_editable(state.online);
        self.completed
            .set_sensitive(state.online && !self.busy.get());
        self.acknowledge
            .set_sensitive(state.online && state.pending_write_review && !self.busy.get());
        self.save
            .set_sensitive(state.online && !state.pending_write_review && !self.busy.get());
        self.delete.set_sensitive(
            state.online
                && !state.pending_write_review
                && !self.busy.get()
                && self.selected.borrow().is_some(),
        );
        self.body.set_visible(self.note());
        self.completed.set_visible(!self.note());
        self.filter.set_visible(!self.note());
    }
    fn check_address(&self) -> bool {
        if address_matches(&self.address.text(), &self.session.borrow().url) {
            return true;
        }
        self.session.borrow_mut().online = false;
        self.save.set_sensitive(false);
        self.delete.set_sensitive(false);
        self.acknowledge.set_sensitive(false);
        self.status
            .set_text("地址已编辑。请先连接应用新地址，再刷新或写入。");
        false
    }
    fn refresh(self: &Rc<Self>) {
        if !self.check_address() {
            return;
        }
        self.start(None, false);
    }
    fn start(
        self: &Rc<Self>,
        operation: Option<(&'static str, String, Option<serde_json::Value>)>,
        clear: bool,
    ) {
        if self.busy.replace(true) {
            return;
        }
        self.status.set_text("正在连接……");
        self.save.set_sensitive(false);
        self.delete.set_sensitive(false);
        self.title.set_sensitive(false);
        self.body.set_sensitive(false);
        self.completed.set_sensitive(false);
        self.list.set_sensitive(false);
        self.kind.set_sensitive(false);
        self.address.set_sensitive(false);
        let placeholder = Session::new(
            self.session.borrow().url.clone(),
            String::new(),
            data_root().join("cache"),
        );
        let mut session = self.session.replace(placeholder);
        let (sender, receiver) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let result = match operation {
                Some((method, path, body)) => session.write(method, &path, body),
                None => session.refresh(),
            };
            let _ = sender.send((session, result));
        });
        let ui = self.clone();
        gtk::glib::timeout_add_local(std::time::Duration::from_millis(50), move || match receiver
            .try_recv()
        {
            Ok((session, result)) => {
                ui.session.replace(session);
                ui.busy.set(false);
                ui.list.set_sensitive(true);
                ui.kind.set_sensitive(true);
                ui.address.set_sensitive(true);
                ui.title.set_sensitive(true);
                ui.body.set_sensitive(true);
                ui.completed.set_sensitive(true);
                if result.is_ok() && clear {
                    ui.clear();
                }
                ui.report(result);
                gtk::glib::ControlFlow::Break
            }
            Err(std::sync::mpsc::TryRecvError::Empty) => gtk::glib::ControlFlow::Continue,
            Err(_) => {
                ui.busy.set(false);
                ui.report(Err("网络任务失败，请重试".into()));
                gtk::glib::ControlFlow::Break
            }
        });
    }
    fn report(&self, result: Result<(), String>) {
        let state = self.session.borrow();
        let time = if state.snapshot.refreshed_at.is_empty() {
            "无成功缓存"
        } else {
            &state.snapshot.refreshed_at
        };
        self.status.set_text(&match result {
            Ok(()) => format!("已连接 · 缓存时间：{}", time),
            Err(e) => format!("只读 · {} · 缓存时间：{}", e, time),
        });
        if state.pending_write_review {
            self.status.set_text(&format!(
                "{} · 写入结果不确定。请刷新检查列表，再点击已核对写入结果。",
                self.status.text()
            ));
        }
        drop(state);
        self.paint();
    }
    fn clear(&self) {
        self.selected.replace(None);
        self.title.set_text("");
        self.body.buffer().set_text("");
        self.completed.set_active(false);
        self.paint();
    }
    fn select(&self, index: usize) {
        if self.busy.get() {
            return;
        }
        let Some(key) = self.visible.borrow().get(index).cloned() else {
            return;
        };
        self.selected.replace(Some(key.clone()));
        let state = self.session.borrow();
        if self.note() {
            if let Some(note) = state.snapshot.notes.iter().find(|v| v.id == key.0) {
                self.title.set_text(&note.title);
                self.body.buffer().set_text(&note.body);
            }
        } else if let Some(task) = state.snapshot.tasks.iter().find(|v| v.id == key.0) {
            self.title.set_text(&task.title);
            self.completed.set_active(task.completed);
        }
        self.delete
            .set_sensitive(state.online && !state.pending_write_review);
    }
    fn save(self: &Rc<Self>) {
        if !self.check_address() {
            return;
        }
        let title = self.title.text().trim().to_string();
        let buffer = self.body.buffer();
        let body = buffer
            .text(&buffer.start_iter(), &buffer.end_iter(), false)
            .to_string();
        if !valid_title(&title) || (self.note() && body.len() > 1024 * 1024) {
            self.status
                .set_text("标题需为 1–200 字符，正文最多 1 MiB。");
            return;
        }
        let mut value = if self.note() {
            serde_json::json!({"title":title,"body":body})
        } else {
            serde_json::json!({"title":title,"completed":self.completed.is_active()})
        };
        let selected = self.selected.borrow().clone();
        let (method, path) = match selected {
            Some((id, revision)) => {
                value["revision"] = revision.into();
                (
                    "PUT",
                    format!("{}/{}", if self.note() { "notes" } else { "tasks" }, id),
                )
            }
            None => ("POST", if self.note() { "notes" } else { "tasks" }.into()),
        };
        self.start(Some((method, path, Some(value))), true);
    }
    fn delete(self: &Rc<Self>) {
        if !self.check_address() {
            return;
        }
        let Some((id, revision)) = self.selected.borrow().clone() else {
            return;
        };
        let path = format!(
            "{}/{}?revision={}",
            if self.note() { "notes" } else { "tasks" },
            id,
            revision
        );
        self.start(Some(("DELETE", path, None)), true);
    }
    fn connect(self: &Rc<Self>) {
        if self.busy.get() {
            return;
        }
        match normalize_url(&self.address.text()) {
            Ok(url) => {
                let root = data_root();
                if let Err(e) = std::fs::create_dir_all(&root)
                    .and_then(|_| std::fs::write(root.join("address.txt"), &url))
                {
                    self.status.set_text(&format!("地址保存失败：{}", e));
                    return;
                }
                let changed = self.session.borrow().url != url;
                if changed {
                    self.session.replace(Session::new(
                        url,
                        self.token.text().to_string(),
                        root.join("cache"),
                    ));
                    self.clear();
                } else {
                    self.session
                        .borrow_mut()
                        .set_token(self.token.text().to_string());
                }
                self.refresh();
            }
            Err(e) => self.status.set_text(&e),
        }
    }
}
fn main() -> gtk::glib::ExitCode {
    let app = gtk::Application::new(
        Some("dev.tasknotes.desktop"),
        gio::ApplicationFlags::FLAGS_NONE,
    );
    app.connect_activate(|app| {
        let root = data_root();
        let url = std::fs::read_to_string(root.join("address.txt"))
            .unwrap_or_else(|_| "http://127.0.0.1:8080".into());
        let window = gtk::ApplicationWindow::builder()
            .application(app)
            .title("TaskNotes")
            .default_width(1060)
            .default_height(720)
            .build();
        let outer = gtk::Box::new(gtk::Orientation::Vertical, 10);
        outer.set_margin_top(16);
        outer.set_margin_bottom(16);
        outer.set_margin_start(16);
        outer.set_margin_end(16);
        let connection = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        let address = gtk::Entry::builder()
            .text(&url)
            .placeholder_text("服务地址")
            .hexpand(true)
            .build();
        let token = gtk::PasswordEntry::builder()
            .placeholder_text("令牌（仅内存）")
            .show_peek_icon(true)
            .build();
        let connect = gtk::Button::with_label("连接 / 应用地址");
        let refresh = gtk::Button::with_label("刷新");
        connection.append(&address);
        connection.append(&token);
        connection.append(&connect);
        connection.append(&refresh);
        outer.append(&connection);
        let toolbar = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        let kind = gtk::DropDown::from_strings(&["任务", "笔记"]);
        let filter = gtk::DropDown::from_strings(&["全部", "未完成", "已完成"]);
        let search = gtk::SearchEntry::builder()
            .placeholder_text("搜索标题和笔记正文")
            .hexpand(true)
            .build();
        let new = gtk::Button::with_label("新建");
        toolbar.append(&kind);
        toolbar.append(&filter);
        toolbar.append(&search);
        toolbar.append(&new);
        outer.append(&toolbar);
        let split = gtk::Paned::new(gtk::Orientation::Horizontal);
        split.set_vexpand(true);
        split.set_position(380);
        let list = gtk::ListBox::new();
        list.set_selection_mode(gtk::SelectionMode::Single);
        let scroll = gtk::ScrolledWindow::builder()
            .child(&list)
            .min_content_width(300)
            .build();
        split.set_start_child(Some(&scroll));
        let editor = gtk::Box::new(gtk::Orientation::Vertical, 10);
        editor.set_margin_start(16);
        let title = gtk::Entry::builder().placeholder_text("标题").build();
        let completed = gtk::CheckButton::with_label("已完成");
        let body = gtk::TextView::builder()
            .wrap_mode(gtk::WrapMode::WordChar)
            .vexpand(true)
            .build();
        let body_scroll = gtk::ScrolledWindow::builder()
            .child(&body)
            .vexpand(true)
            .build();
        let actions = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        let save = gtk::Button::with_label("保存");
        let delete = gtk::Button::with_label("删除所选");
        let acknowledge = gtk::Button::with_label("已核对写入结果");
        actions.append(&save);
        actions.append(&delete);
        actions.append(&acknowledge);
        editor.append(&title);
        editor.append(&completed);
        editor.append(&body_scroll);
        editor.append(&actions);
        split.set_end_child(Some(&editor));
        outer.append(&split);
        let status = gtk::Label::builder()
            .xalign(0.0)
            .wrap(true)
            .label("未验证连接；缓存只读。输入令牌后连接。")
            .build();
        outer.append(&status);
        window.set_child(Some(&outer));
        let ui = Rc::new(Ui {
            window,
            address,
            token,
            kind,
            filter,
            search,
            list,
            title,
            body,
            completed,
            status,
            save,
            delete,
            acknowledge,
            session: RefCell::new(Session::new(url, String::new(), root.join("cache"))),
            selected: RefCell::new(None),
            visible: RefCell::new(Vec::new()),
            busy: Cell::new(false),
        });
        {
            let u = ui.clone();
            connect.connect_clicked(move |_| u.connect());
        }
        {
            let u = ui.clone();
            refresh.connect_clicked(move |_| u.refresh());
        }
        {
            let u = ui.clone();
            new.connect_clicked(move |_| {
                if !u.busy.get() {
                    u.clear();
                }
            });
        }
        {
            let u = ui.clone();
            ui.acknowledge.connect_clicked(move |_| {
                let result = u.session.borrow_mut().acknowledge_write();
                u.report(result);
            });
        }
        {
            let u = ui.clone();
            ui.save.connect_clicked(move |_| u.save());
        }
        {
            let u = ui.clone();
            ui.delete.connect_clicked(move |_| u.delete());
        }
        {
            let u = ui.clone();
            ui.kind.connect_selected_notify(move |_| {
                if !u.busy.get() {
                    u.clear();
                }
            });
        }
        {
            let u = ui.clone();
            ui.filter.connect_selected_notify(move |_| u.paint());
        }
        {
            let u = ui.clone();
            ui.search.connect_search_changed(move |_| u.paint());
        }
        {
            let u = ui.clone();
            ui.list
                .connect_row_activated(move |_, row| u.select(row.index() as usize));
        }
        {
            let u = ui.clone();
            ui.address.connect_changed(move |_| {
                u.session.borrow_mut().online = false;
                u.save.set_sensitive(false);
                u.delete.set_sensitive(false);
                u.status
                    .set_text("地址已编辑。点击连接应用；当前数据只读。");
            });
        }
        {
            let u = ui.clone();
            ui.window.connect_is_active_notify(move |w| {
                if w.is_active() {
                    u.refresh();
                }
            });
        }
        ui.paint();
        ui.window.present();
    });
    app.run()
}
