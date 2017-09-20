/*
 * UsersBox.vala
 *
 * Copyright 2012-17 Tony George <teejeetech@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 *
 */

using Gtk;
using Gee;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.JsonHelper;
using TeeJee.ProcessHelper;
using TeeJee.GtkHelper;
using TeeJee.System;
using TeeJee.Misc;

class UsersBox : Gtk.Box{
	
	private Gtk.TreeView treeview;
	private Gtk.Window parent_window;
	private ExcludeBox exclude_box;
	
	public UsersBox (Gtk.Window _parent_window, ExcludeBox _exclude_box) {

		log_debug("UsersBox: UsersBox()");
		
		//base(Gtk.Orientation.VERTICAL, 6); // issue with vala
		Object(orientation: Gtk.Orientation.VERTICAL, spacing: 6); // work-around
		parent_window = _parent_window;
		margin = 12;

		exclude_box = _exclude_box;

		var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
		add(box);
		
		add_label_header(box, _("User Home Directories"), true);

		var label = add_label(this, _("User home directories are excluded by default unless you enable them here"));

		var buffer = add_label(box, "");
		buffer.hexpand = true;

		//init_exclude_summary_link(box);

		init_treeview();

		//init_actions();
		
		refresh_treeview();

		log_debug("UsersBox: UsersBox(): exit");
    }

    private void init_treeview(){
		
		// treeview
		treeview = new TreeView();
		treeview.get_selection().mode = SelectionMode.MULTIPLE;
		treeview.headers_visible = true;
		treeview.rules_hint = true;
		treeview.reorderable = true;
		treeview.set_tooltip_text(_("Click to edit. Drag and drop to re-order."));
		//treeview.row_activated.connect(treeview_row_activated);

		// scrolled
		var scrolled = new ScrolledWindow(null, null);
		scrolled.set_shadow_type (ShadowType.ETCHED_IN);
		scrolled.add (treeview);
		scrolled.expand = true;
		add(scrolled);

		// column
		var col = new TreeViewColumn();
		col.title = _("User");
		treeview.append_column(col);

		// name
		var cell_text = new CellRendererText ();
		col.pack_start (cell_text, false);
		
		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter)=>{
			SystemUser user;
			model.get(iter, 0, out user);
			(cell as Gtk.CellRendererText).text = user.name;
		});

		// column
		col = new TreeViewColumn();
		col.title = _("Home");
		treeview.append_column(col);

		// name
		cell_text = new CellRendererText ();
		col.pack_start (cell_text, false);
		
		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter)=>{
			SystemUser user;
			model.get(iter, 0, out user);
			(cell as Gtk.CellRendererText).text = user.home_path;
		});

		// column
		col = new TreeViewColumn();
		col.title = _("Include hidden items in home");
		treeview.append_column(col);
		
		// radio_include
		var cell_radio = new Gtk.CellRendererToggle();
		cell_radio.xpad = 2;
		cell_radio.activatable = true;
		col.pack_start (cell_radio, false);

		col.set_attributes(cell_radio, "active", 1);
		
		cell_radio.toggled.connect((cell, path)=>{

			log_debug("cell_include.toggled()");
			
			var model = (Gtk.ListStore) treeview.model;
			TreeIter iter;
			
			bool enabled;
			model.get_iter_from_string (out iter, path);
			model.get(iter, 1, out enabled);
			enabled = !enabled;
			model.set(iter, 1, enabled);

			SystemUser user;
			model.get(iter, 0, out user);

			string pattern = "+ %s/.**".printf(user.home_path);
			
			if (enabled){
				
				if (user.has_encrypted_home){
					
					string txt = _("Encrypted Home Directory");

					string msg = _("This user has an encrypted home directory. It's not possible to include only hidden files.");
					
					gtk_messagebox(txt, msg, parent_window, true);

					return;
				}
				
				if (!App.exclude_list_user.contains(pattern)){
					App.exclude_list_user.add(pattern);
				}
			}
			else{
				if (App.exclude_list_user.contains(pattern)){
					App.exclude_list_user.remove(pattern);
				}
			}

			exclude_box.refresh_treeview();
		});

		// column
		col = new TreeViewColumn();
		col.title = _("Include everything in home");
		treeview.append_column(col);

		// radio_exclude
		cell_radio = new Gtk.CellRendererToggle();
		cell_radio.xpad = 2;
		cell_radio.activatable = true;
		col.pack_start (cell_radio, false);
		
		col.set_attributes(cell_radio, "active", 2);

		cell_radio.toggled.connect((cell, path)=>{

			var model = (Gtk.ListStore) treeview.model;
			TreeIter iter;
			model.get_iter_from_string (out iter, path);

			bool enabled;
			model.get(iter, 2, out enabled);
			enabled = !enabled;
			model.set(iter, 2, enabled);

			SystemUser user;
			model.get(iter, 0, out user);

			string pattern = "+ %s/**".printf(user.home_path);

			if (user.has_encrypted_home){
				pattern = "+ /home/.ecryptfs/%s/***".printf(user.name);
			}
			
			if (enabled){
				if (!App.exclude_list_user.contains(pattern)){
					App.exclude_list_user.add(pattern);
				}
			}
			else{
				if (App.exclude_list_user.contains(pattern)){
					App.exclude_list_user.remove(pattern);
				}
			}

			exclude_box.refresh_treeview();
		});
	}

	// helpers

	public void refresh_treeview(){
		
		var model = new Gtk.ListStore(3, typeof(SystemUser), typeof(bool), typeof(bool));
		treeview.model = model;

		TreeIter iter;
		
		foreach(var user in App.current_system_users.values){

			if (user.is_system){ continue; }

			model.append(out iter);
			model.set (iter, 0, user);
			model.set (iter, 1, App.exclude_list_user.contains("+ %s/.**".printf(user.home_path)));
			model.set (iter, 2, App.exclude_list_user.contains("+ %s/**".printf(user.home_path)));
		}
	}

	public void save_changes(){

		//App.exclude_list_user.clear();

		// add include patterns from treeview
		/*TreeIter iter;
		var store = (Gtk.ListStore) treeview.model;
		bool iterExists = store.get_iter_first (out iter);
		while (iterExists) {
			string pattern;
			store.get(iter, 0, out pattern);

			if (!App.exclude_list_user.contains(pattern)
				&& !App.exclude_list_default.contains(pattern)
				&& !App.exclude_list_home.contains(pattern)){
				
				App.exclude_list_user.add(pattern);
			}
			
			iterExists = store.iter_next(ref iter);
		}*/

		log_debug("save_changes(): exclude_list_user:");
		foreach(var item in App.exclude_list_user){
			log_debug(item);
		}
		log_debug("");
	}
}
