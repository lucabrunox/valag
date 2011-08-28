/* valacompiler.vala
 *
 * Copyright (C) 2010  Luca Bruno
 * Copyright (C) 2006-2009  Jürg Billeter
 * Copyright (C) 1996-2002, 2004, 2005, 2006 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Jürg Billeter <j@bitron.ch>
 * 	Luca Bruno <lethalman88@gmail.com>
 */

/*
 * This is a slightly modified version of valacompiler.vala of the Vala package.
 */

using GLib;
using Vala;

class Valag.GraphContext : CodeContext
{
  public bool concentrate;
}

class Valag.Application
{
  static bool concentrate;
  static string format;
  static string prefix;

  const OptionEntry[] graph_options = {
    { "concentrate", 'c', 0, OptionArg.NONE, ref concentrate, "Concentrate edges", null },
    { "format", 'f', 0, OptionArg.STRING, ref format, "Graphviz output format (default: 'xdot')", "FORMAT" },
    { "prefix", 'p', 0, OptionArg.STRING, ref prefix, "Output filenames prefix (default: '')", "PREFIX" },
    { "", 0, 0, OptionArg.FILENAME_ARRAY, ref sources, null, "FILE..." },
    { null }
  };

  static string basedir;
  static string directory;
  static bool version;
  [CCode (array_length = false, array_null_terminated = true)]
  static string[] sources;
  [CCode (array_length = false, array_null_terminated = true)]
  static string[] vapi_directories;
  [CCode (array_length = false, array_null_terminated = true)]
  static string[] gir_directories;
  static string gir;
  [CCode (array_length = false, array_null_terminated = true)]
  static string[] packages;

  static string internal_header_filename;
  static string symbols_filename;
  static string includedir;
  static bool debug;
  static bool disable_assert;
  static bool enable_checking;
  static bool deprecated;
  static bool experimental;
  static bool experimental_non_null;
  static bool disable_warnings;
  [CCode (array_length = false, array_null_terminated = true)]
  static string[] defines;
  static bool quiet_mode;
  static bool verbose_mode;
  static string profile;
  static bool nostdpkg;
  static bool fatal_warnings;

  static string entry_point;

  private GraphContext context;

  const OptionEntry[] vala_options = {
    { "girdir", 0, 0, OptionArg.FILENAME_ARRAY, ref gir_directories, "Look for .gir files in DIRECTORY", "DIRECTORY..." },
    { "vapidir", 0, 0, OptionArg.FILENAME_ARRAY, ref vapi_directories, "Look for package bindings in DIRECTORY", "DIRECTORY..." },
    { "pkg", 0, 0, OptionArg.STRING_ARRAY, ref packages, "Include binding for PACKAGE", "PACKAGE..." },
    { "gir", 0, 0, OptionArg.STRING, ref gir, "GObject-Introspection repository file name", "NAME-VERSION.gir" },
    { "basedir", 'b', 0, OptionArg.FILENAME, ref basedir, "Base source directory", "DIRECTORY" },
    { "directory", 'd', 0, OptionArg.FILENAME, ref directory, "Output directory", "DIRECTORY" },
    { "version", 0, 0, OptionArg.NONE, ref version, "Display version number", null },
    { "includedir", 0, 0, OptionArg.FILENAME, ref includedir, "Directory used to include the C header file", "DIRECTORY" },
    { "symbols", 0, 0, OptionArg.FILENAME, ref symbols_filename, "Output symbols file", "FILE" },
    { "debug", 'g', 0, OptionArg.NONE, ref debug, "Produce debug information", null },
    { "define", 'D', 0, OptionArg.STRING_ARRAY, ref defines, "Define SYMBOL", "SYMBOL..." },
    { "main", 0, 0, OptionArg.STRING, ref entry_point, "Use SYMBOL as entry point", "SYMBOL..." },
    { "nostdpkg", 0, 0, OptionArg.NONE, ref nostdpkg, "Do not include standard packages", null },
    { "disable-assert", 0, 0, OptionArg.NONE, ref disable_assert, "Disable assertions", null },
    { "enable-checking", 0, 0, OptionArg.NONE, ref enable_checking, "Enable additional run-time checks", null },
    { "enable-deprecated", 0, 0, OptionArg.NONE, ref deprecated, "Enable deprecated features", null },
    { "enable-experimental", 0, 0, OptionArg.NONE, ref experimental, "Enable experimental features", null },
    { "disable-warnings", 0, 0, OptionArg.NONE, ref disable_warnings, "Disable warnings", null },
    { "fatal-warnings", 0, 0, OptionArg.NONE, ref fatal_warnings, "Treat warnings as fatal", null },
    { "enable-experimental-non-null", 0, 0, OptionArg.NONE, ref experimental_non_null, "Enable experimental enhancements for non-null types", null },
    { "profile", 0, 0, OptionArg.STRING, ref profile, "Use the given profile instead of the default", "PROFILE" },
    { "quiet", 'q', 0, OptionArg.NONE, ref quiet_mode, "Do not print messages to the console", null },
    { "verbose", 'v', 0, OptionArg.NONE, ref verbose_mode, "Print additional messages to the console", null },
    { null }
  };
	
  private int quit () {
    if (context.report.get_errors () == 0 && context.report.get_warnings () == 0) {
      return 0;
    }
    if (context.report.get_errors () == 0) {
      if (!quiet_mode) {
        stdout.printf ("Compilation succeeded - %d warning(s)\n", context.report.get_warnings ());
      }
      return 0;
    } else {
      if (!quiet_mode) {
        stdout.printf ("Compilation failed: %d error(s), %d warning(s)\n", context.report.get_errors (), context.report.get_warnings ());
      }
      return 1;
    }
  }

  private int run () {
    context = new GraphContext ();
    CodeContext.push (context);

    // graph
    context.concentrate = concentrate;

    // vala
    context.assert = !disable_assert;
    context.checking = enable_checking;
    context.deprecated = deprecated;
    context.experimental = experimental;
    context.experimental_non_null = experimental || experimental_non_null;
    context.report.enable_warnings = !disable_warnings;
    context.report.set_verbose_errors (!quiet_mode);
    context.verbose_mode = verbose_mode;

    context.compile_only = true;
    context.internal_header_filename = internal_header_filename;
    context.symbols_filename = symbols_filename;
    context.includedir = includedir;
    if (basedir == null) {
      context.basedir = CodeContext.realpath (".");
    } else {
      context.basedir = CodeContext.realpath (basedir);
    }
    if (directory != null) {
      context.directory = CodeContext.realpath (directory);
    } else {
      context.directory = context.basedir;
    }
    context.vapi_directories = vapi_directories;
    context.gir_directories = gir_directories;
    context.debug = debug;
    if (profile == "posix") {
      context.profile = Profile.POSIX;
      context.add_define ("POSIX");
    } else if (profile == "gobject-2.0" || profile == "gobject" || profile == null) {
      // default profile
      context.profile = Profile.GOBJECT;
      context.add_define ("GOBJECT");
      context.add_define ("VALA_0_7_6_NEW_METHODS");
    } else {
      Report.error (null, "Unknown profile %s".printf (profile));
    }

    context.entry_point_name = entry_point;

    if (defines != null) {
      foreach (string define in defines) {
        context.add_define (define);
      }
    }

    for (int i = 2; i <= 12; i += 2) {
      context.add_define ("VALA_0_%d".printf (i));
    }

    if (context.profile == Profile.POSIX) {
      if (!nostdpkg) {
        /* default package */
        context.add_external_package ("posix");
      }
    } else if (context.profile == Profile.GOBJECT) {
      int glib_minor = 16;

      for (int i = 16; i <= glib_minor; i += 2) {
        context.add_define ("GLIB_2_%d".printf (i));
      }

      if (!nostdpkg) {
        /* default packages */
        context.add_external_package ("glib-2.0");
        context.add_external_package ("gobject-2.0");
      }
    } else if (context.profile == Profile.DOVA) {
      if (!nostdpkg) {
        /* default package */
        context.add_external_package ("dova-core-0.1");
      }
    }

    if (packages != null) {
      foreach (string package in packages) {
        context.add_external_package (package);
        if (context.profile == Profile.GOBJECT && package == "dbus-glib-1") {
          context.add_define ("DBUS_GLIB");
        }
      }
      packages = null;
    }

    if (context.report.get_errors () > 0 || (fatal_warnings && context.report.get_warnings () > 0)) {
      return quit ();
    }
		
    foreach (string source in sources) {
      context.add_source_filename (source);
    }
    sources = null;

    if (context.report.get_errors () > 0 || (fatal_warnings && context.report.get_warnings () > 0)) {
      return quit ();
    }
	
    var parser = new Parser ();
    parser.parse (context);

    var genie_parser = new Genie.Parser ();
    genie_parser.parse (context);

    var gir_parser = new GirParser ();
    gir_parser.parse (context);

    if (context.report.get_errors () > 0 || (fatal_warnings && context.report.get_warnings () > 0)) {
      return quit ();
    }

    // initial graph
    var graph_generator = new GraphGenerator ("valainitial");
    var graph = graph_generator.generate (context);

    if (context.report.get_errors () > 0 || (fatal_warnings && context.report.get_warnings () > 0)) {
      return quit ();
    }

    var gvformat = format ?? "xdot";
    var fileprefix = prefix ?? "";

    var gvcontext = new Gvc.Context ();
    gvcontext.layout (graph, "dot");
    gvcontext.render_filename (graph, gvformat, fileprefix+"valainitial."+gvformat);
    context.resolver.resolve (context);

    if (context.report.get_errors () > 0 || (fatal_warnings && context.report.get_warnings () > 0)) {
      return quit ();
    }

    // after resolver graph
    graph_generator = new GraphGenerator ("valaresolved");
    graph = graph_generator.generate (context);

    if (context.report.get_errors () > 0 || (fatal_warnings && context.report.get_warnings () > 0)) {
      return quit ();
    }

    gvcontext = new Gvc.Context ();
    gvcontext.layout (graph, "dot");
    gvcontext.render_filename (graph, gvformat, fileprefix+"valaresolved."+gvformat);

    context.analyzer.analyze (context);

    if (context.report.get_errors () > 0 || (fatal_warnings && context.report.get_warnings () > 0)) {
      return quit ();
    }

    // after semantic analyzer graph
    graph_generator = new GraphGenerator ("valaanalyzed");
    graph = graph_generator.generate (context);

    if (context.report.get_errors () > 0 || (fatal_warnings && context.report.get_warnings () > 0)) {
      return quit ();
    }

    gvcontext = new Gvc.Context ();
    gvcontext.layout (graph, "dot");
    gvcontext.render_filename (graph, gvformat, fileprefix+"valaanalyzed."+gvformat);

    context.flow_analyzer.analyze (context);

    if (context.report.get_errors () > 0 || (fatal_warnings && context.report.get_warnings () > 0)) {
      return quit ();
    }

    // flow analyzer graph
    var flow_graph_generator = new FlowGraphGenerator ("valaflow");
    graph = flow_graph_generator.generate (context);

    if (context.report.get_errors () > 0 || (fatal_warnings && context.report.get_warnings () > 0)) {
      return quit ();
    }

    gvcontext = new Gvc.Context ();
    gvcontext.layout (graph, "dot");
    gvcontext.render_filename (graph, gvformat, fileprefix+"valaflow."+gvformat);

	// final graph
    graph_generator = new GraphGenerator ("valafinal");
    graph = graph_generator.generate (context);

    if (context.report.get_errors () > 0 || (fatal_warnings && context.report.get_warnings () > 0)) {
      return quit ();
    }

    gvcontext = new Gvc.Context ();
    gvcontext.layout (graph, "dot");
    gvcontext.render_filename (graph, gvformat, fileprefix+"valafinal."+gvformat);

    return quit ();
  }

  static int main (string[] args) {
    try {
      var opt_context = new OptionContext ("- Valag Graph Generator");
      opt_context.set_help_enabled (true);

      opt_context.add_main_entries (graph_options, null);

      var vala_group = new OptionGroup ("vala", "Vala compiler options", "Show vala options");
      vala_group.add_entries (vala_options);
      opt_context.add_group ((owned)vala_group);

      opt_context.parse (ref args);
    } catch (OptionError e) {
      stdout.printf ("%s\n", e.message);
      stdout.printf ("Run '%s --help' to see a full list of available command line options.\n", args[0]);
      return 1;
    }
		
    if (version) {
      stdout.printf ("Valag 1.1\n");
      return 0;
    }
		
    if (sources == null) {
      stderr.printf ("No source file specified.\n");
      return 1;
    }

    Gvc.init ();
    var application = new Application ();
    return application.run ();
  }
}
