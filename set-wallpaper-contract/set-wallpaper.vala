/*
* Copyright 2017-2023 elementary, Inc. (https://elementary.io)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 3 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*/

public class SetWallpaperContractor : Gtk.Application {
    const int DEFAULT_TRANSITION_DURATION = 1;
    const string SLIDESHOW_FILENAME = "slideshow.xml";

    const string SLIDESHOW_TEMPLATE = """
    <background>
        %s
    </background>""";

    const string SLIDESHOW_WALLPAPER_TEMPLATE = """
        <static>
            <duration>%i</duration>
            <file>%s</file>
        </static>
        <transition>
            <duration>%i</duration>
            <from>%s</from>
            <to>%s</to>
        </transition>
    """;

    private int delay_value = 60;

    public SetWallpaperContractor () {
        Object (
            application_id: "io.elementary.contract.set-wallpaper",
            flags: GLib.ApplicationFlags.HANDLES_OPEN
        );
    }

    private void update_slideshow (string path, List<File> files, int duration) {
        var wallpapers = "";
        var len = files.length ();
        for (var i = 0; i < len; i++) {
            var slide = files.nth_data (i).get_path ();
            var next_slide = files.nth_data (i - 1 == len ? 0 : i).get_path ();

            wallpapers += SLIDESHOW_WALLPAPER_TEMPLATE.printf (duration, slide,
                DEFAULT_TRANSITION_DURATION, slide, next_slide);
        }

        var slideshow = SLIDESHOW_TEMPLATE.printf (wallpapers);

        try {
            FileUtils.set_contents (path, slideshow);
        } catch (Error e) {
            error (e.message);
        }

        set_settings_key ("file://" + path);
    }

    private void set_settings_key (string uri) {
        var settings = new Settings ("org.gnome.desktop.background");
        settings.set_string ("picture-uri", uri);
        // We don't do gradient backgrounds, reset the key that might interfere
        settings.reset ("color-shading-type");
        if (settings.get_string ("picture-options") == "none") {
            settings.reset ("picture-options");
        }
        settings.apply ();
        Settings.sync ();
    }

    private void delay_value_changed (Gtk.Scale duration_scale, Gtk.Label duration_label) {
        double value = duration_scale.adjustment.value;

        // f(x)=x^5 allows to have fine-grained values (seconds) to the left
        // and very coarse-grained values (hours) to the right of the slider.
        // We limit maximum value to 1 day and minimum to 5 seconds.
        delay_value = (int) (Math.pow (value, 5) / Math.pow (90, 5) * 60 * 60 * 24 + 5);

        // convert to text and remove fractions from values > 1 minute
        string text;
        if (delay_value < 60) {
            text = dngettext (Constants.GETTEXT_DOMAIN, "%d second", "%d seconds", delay_value).printf (delay_value);
        } else if (delay_value < 60 * 60) {
            int minutes = delay_value / 60;
            text = dngettext (Constants.GETTEXT_DOMAIN, "%d minute", "%d minutes", minutes).printf (minutes);
            delay_value = minutes * 60;
        } else if (delay_value < 60 * 60 * 24) {
            int hours = delay_value / (60 * 60);
            text = dngettext (Constants.GETTEXT_DOMAIN, "%d hour", "%d hours", hours).printf (hours);
            delay_value = hours * (60 * 60);
        } else {
            text = _("1 day");
            delay_value = 60 * 60 * 24;
        }

        duration_label.set_markup (_("Show each photo for") + " <b>" + text + "</b>");
    }

    public override void open (File[] gfiles, string hint) {
        var files = new List<File> ();
        foreach (var gfile in gfiles) {
            File append_file = gfile;

            if (!PantheonShell.WallpaperOperation.get_is_file_in_bg_dir (gfile)) {
                var local_file = PantheonShell.WallpaperOperation.copy_for_library (gfile);
                if (local_file != null) {
                    append_file = local_file;
                }
            }

            files.append (append_file);
        }

        if (files.length () == 1) {
            set_settings_key (files.data.get_uri ());
            return;
        }

        var duration = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 100, 10) {
            draw_value = false,
            hexpand = true
        };
        duration.set_value (50);

        var dialog = new Granite.MessageDialog.with_image_from_icon_name (
            _("Set As Desktop Slideshow"),
            "",
            "preferences-desktop-wallpaper",
            Gtk.ButtonsType.CANCEL
        ) {
            badge_icon = new ThemedIcon ("media-playback-start"),
            application = this
        };
        dialog.add_button (_("Create Slideshow"), Gtk.ResponseType.OK);
        dialog.set_default_response (Gtk.ResponseType.OK);
        dialog.custom_bin.append (duration);
        dialog.present ();

        delay_value_changed (duration, dialog.secondary_label);
        duration.value_changed.connect (() => delay_value_changed (duration, dialog.secondary_label));

        dialog.response.connect ((response_id) => {
            if (response_id == Gtk.ResponseType.OK) {
                var path = Path.build_filename (PantheonShell.WallpaperOperation.get_local_bg_directory (), SLIDESHOW_FILENAME);
                update_slideshow (path, files, delay_value);
            }

            dialog.destroy ();
        });
    }

    public static int main (string[] args) {
        if (args.length == 1) {
            warning ("No images specified, aborting.");
            return 1;
        }

        return new SetWallpaperContractor ().run (args);
    }
}
