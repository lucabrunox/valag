/*
    Copyright © 2010 Luca Bruno

    This file is part of Valag.

    Valag is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Valag is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with valag.  If not, see <http://www.gnu.org/licenses/>.
*/

using Vala;
using Gvc;

public class Valag.FlowGraphGenerator : CodeVisitor
{
  private GraphContext context;
  private Graph graph;
  private unowned Graph current_cluster;
  private Gvc.Node parent_node;
  private Set<BasicBlock> visited = new HashSet<BasicBlock>();
  private int next_cluster;

  public FlowGraphGenerator (string graph_name)
    {
      graph = new Graph (graph_name, GraphKind.AGDIGRAPH);
    }
  
  private struct RecordEntry
  {
    public string name;
    public string? value;
  }

  /**
   * Generate a graphviz dot file of the control flows in the specified context.
   *
   * @param context a code context
   */
  public Graph generate (CodeContext context) {
    this.context = (GraphContext)context;
    if (this.context.concentrate)
      graph.safe_set ("concentrate", "true", "");

    /* we're only interested in non-pkg source files */
    var source_files = context.get_source_files ();
    foreach (SourceFile file in source_files) {
      if (!file.external_package) {
        file.accept (this);
      }
    }

    return (owned)graph;
  }

  private string escape_gvlabel (string label)
  {
    // TODO: improve this
    return label.replace("\\", "\\\\").replace("<", "\\<").replace(">", "\\>");
  }

  private Gvc.Node create_node (void* obj, string? name, RecordEntry[] entries)
  {
    var node_name = @"node$((long)obj)";
    var node = graph.find_node (node_name);
    if (node != null)
      return node;

    if (obj is BasicBlock)
      node = current_cluster.create_node (node_name);
    else
      node = graph.create_node (node_name);

    node.safe_set ("shape", "record", "");
    if (obj is BasicBlock && name != "BasicBlock")
      node.safe_set ("shape", "Mrecord", "");

    if (obj is CodeNode || obj is SourceFile)
      node.safe_set ("color", "gray", "");
    else
      node.safe_set ("color", "black", "");

    var label = new StringBuilder();
    label.append (@"{ $(name)");
    foreach (weak RecordEntry entry in entries)
    {
      if (entry.value != null && entry.value != "false")
        label.append (@" | { $(escape_gvlabel(entry.name)) | $(escape_gvlabel(entry.value)) }");
    }
    label.append (" }");
    node.safe_set ("label", label.str, "");

    return (owned)node;
  }

  private unowned Gvc.Graph create_cluster ()
  {
    return graph.create_subgraph (@"cluster_$(next_cluster++)");
  }

  private Gvc.Node visit_graph_node (CodeNode codenode, string? name, RecordEntry[] entries)
  {
    var node = create_node (codenode, name, entries);
    if (parent_node != null)
      {
        var edge = graph.find_edge (parent_node, node);
        if (edge == null)
          graph.create_edge (parent_node, node);
      }

    var old_parent = parent_node;
    parent_node = node;
    codenode.accept_children (this);
    parent_node = old_parent;

    return node;
  }

  private Gvc.Node visit_basic_block (BasicBlock block, bool is_entry = false)
  {
    string label = "BasicBlock";
    if (is_entry)
      label = "EntryBlock";
    else if (block.get_successors().size == 0)
      label = "ExitBlock";

    var node = create_node (block, label, {});
    var edge = graph.find_edge (parent_node, node);
    if (edge == null)
      graph.create_edge (parent_node, node);

    if (!(block in visited))
      {
        visited.add (block);
        var old_parent = parent_node;
        parent_node = node;
        foreach (var succ in block.get_successors ())
          visit_basic_block (succ);
        foreach (var codenode in block.get_nodes ())
          codenode.accept (this);
        parent_node = old_parent;
      }
    
    return node;
  }

  // visitor

  public override void visit_source_file (SourceFile source_file)
  {
    var node = create_node (source_file, "SourceFile",
                            {RecordEntry() {name="filename", value=source_file.filename}});
    var old_parent = parent_node;
    parent_node = node;
    source_file.accept_children (this);
    parent_node = old_parent;
  }

  public override void visit_namespace (Namespace ns)
  {
    visit_graph_node (ns, @"Namespace $(ns.get_full_name())", {});
  }

  public override void visit_class (Class cl)
  {
    visit_graph_node (cl, @"Class $(cl.get_full_name())", {});
  }

  public override void visit_struct (Struct st)
  {
    visit_graph_node (st, @"Struct $(st.get_full_name())", {});
  }

  public override void visit_enum (Vala.Enum en)
  {
    visit_graph_node (en, @"Enum $(en.get_full_name())", {});
  }

  public override void visit_enum_value (Vala.EnumValue ev)
  {
    visit_graph_node (ev, @"EnumValue $(ev.name)", {});
  }

  public override void visit_error_domain (ErrorDomain edomain)
  {
    visit_graph_node (edomain, @"ErrorDomain $(edomain.get_full_name())", {});
  }

  public override void visit_error_code (ErrorCode ecode)
  {
    visit_graph_node (ecode, @"ErrorCode $(ecode.name)", {});
  }

  public override void visit_delegate (Delegate d)
  {
    visit_graph_node (d, @"Delegate $(d.name)", {});
  }

  public override void visit_member (Member m)
  {
    m.accept_children (this);
  }

  public override void visit_constant (Constant c)
  {
    visit_graph_node (c, @"Constant $(c.name)", {});
  }

  public override void visit_field (Field f)
  {
    visit_graph_node (f, @"Field $(f.name)", {});
  }

  public override void visit_method (Method m)
  {
    var label = "Method";
    if (m is DynamicMethod)
      label = "DynamicMethod";
    var node = visit_graph_node (m, @"$(label) $(m.name)",
                                 {RecordEntry(){name="is_abstract", value=m.is_abstract.to_string()},
                                  RecordEntry(){name="is_virtual", value=m.is_virtual.to_string()},
                                  RecordEntry(){name="overrides", value=m.overrides.to_string()},
                                  RecordEntry(){name="closure", value=m.closure.to_string()},
                                  RecordEntry(){name="coroutine", value=m.coroutine.to_string()}});
    var old_parent = parent_node;
    unowned Gvc.Graph old_cluster = current_cluster;
    parent_node = node;
    current_cluster = create_cluster ();
    visit_basic_block (m.entry_block, true);
    parent_node = old_parent;
    current_cluster = old_cluster;
  }

  public override void visit_creation_method (CreationMethod m)
  {
    visit_graph_node (m, @"CreationMethod $(m.name)",
                      {RecordEntry(){name="chain_up", value=m.chain_up.to_string()}});
  }

  public override void visit_formal_parameter (FormalParameter p)
  {
    string? direction = null;
    if (p.direction == ParameterDirection.OUT)
      direction = "out";
    else if (p.direction == ParameterDirection.REF)
      direction = "ref";
    visit_graph_node (p, @"FormalParameter $(p.name)",
                      {RecordEntry() {name="ellipsis", value=p.ellipsis.to_string()},
                       RecordEntry() {name="direction", value=direction}});
  }

  public override void visit_property (Property prop)
  {
    visit_graph_node (prop, @"Property $(prop.name)",
                      {RecordEntry(){name="notify", value=prop.notify.to_string()},
                       RecordEntry(){name="is_abstract", value=prop.is_abstract.to_string()},
                       RecordEntry(){name="is_virtual", value=prop.is_virtual.to_string()},
                       RecordEntry(){name="overrides", value=prop.overrides.to_string()}});
  }

  public override void visit_property_accessor (PropertyAccessor acc)
  {
    visit_graph_node (acc, @"PropertyAccessor",
                      {RecordEntry(){name="automatic_body", value=acc.automatic_body.to_string()}});
  }

  public override void visit_signal (Vala.Signal sig)
  {
    var label = "Signal";
    if (sig is DynamicSignal)
      label = "DynamicSignal";
    visit_graph_node (sig, @"$(label) $(sig.name)", {});
  }

  public override void visit_constructor (Constructor c)
  {
    visit_graph_node (c, @"Constructor $(c.name)", {});
  }

  public override void visit_destructor (Destructor d)
  {
    visit_graph_node (d, "Destructor", {});
  }

  public override void visit_type_parameter (TypeParameter p)
  {
    visit_graph_node (p, @"TypeParameter $(p.name)", {});
  }

  public override void visit_using_directive (UsingDirective ns)
  {
    visit_graph_node (ns, "UsingDirective", {});
  }

  public override void visit_data_type (DataType type)
  {
    visit_graph_node (type, "DataType",
                      {RecordEntry(){name="value_owned", value=type.value_owned.to_string()},
                       RecordEntry(){name="nullable", value=type.nullable.to_string()},
                       RecordEntry(){name="is_dynamic", value=type.is_dynamic.to_string()},
                       RecordEntry(){name="float_ref", value=type.floating_reference.to_string()}});
  }
  
  public override void visit_block (Block b)
  {
    visit_graph_node (b, "Block",
                      {RecordEntry(){name="captured", value=b.captured.to_string()}});
  }

  public override void visit_empty_statement (EmptyStatement stmt)
  {
    visit_graph_node (stmt, "EmptyStatement", {});
  }

  public override void visit_declaration_statement (DeclarationStatement stmt)
  {
    visit_graph_node (stmt, "DeclarationStatement", {});
  }

  public override void visit_local_variable (LocalVariable local)
  {
    visit_graph_node (local, @"LocalVariable $(local.name)",
                      {RecordEntry(){name="is_result", value=local.is_result.to_string()},
                       RecordEntry(){name="floating", value=local.floating.to_string()},
                       RecordEntry(){name="captured", value=local.captured.to_string()}});
  }

  public override void visit_initializer_list (InitializerList list)
  {
    visit_graph_node (list, "InitializerList", {});
  }

  public override void visit_expression_statement (ExpressionStatement stmt)
  {
    visit_graph_node (stmt, "ExpressionStatement", {});
  }

  public override void visit_if_statement (IfStatement stmt)
  {
    visit_graph_node (stmt, "IfStatement", {});
  }

  public override void visit_switch_statement (SwitchStatement stmt)
  {
    visit_graph_node (stmt, "SwitchStatement", {});
  }

  public override void visit_switch_section (SwitchSection section)
  {
    visit_graph_node (section, "SwitchSection", {});
  }

  public override void visit_switch_label (SwitchLabel label)
  {
    visit_graph_node (label, "SwitchLabel", {});
  }

  public override void visit_loop (Loop stmt)
  {
    visit_graph_node (stmt, "Loop", {});
  }

  public override void visit_while_statement (WhileStatement stmt)
  {
    visit_graph_node (stmt, "WhileStatement", {});
  }

  public override void visit_do_statement (DoStatement stmt)
  {
    visit_graph_node (stmt, "DoStatement", {});
  }

  public override void visit_for_statement (ForStatement stmt)
  {
    visit_graph_node (stmt, "ForStatement", {});
  }

  public override void visit_foreach_statement (ForeachStatement stmt)
  {
    visit_graph_node (stmt, "ForeachStatement",
                      {RecordEntry(){name="variable_name", value=stmt.variable_name}});
  }

  public override void visit_break_statement (BreakStatement stmt)
  {
    visit_graph_node (stmt, "BreakStatement", {});
  }

  public override void visit_continue_statement (ContinueStatement stmt)
  {
    visit_graph_node (stmt, "ContinueStatement", {});
  }

  public override void visit_return_statement (ReturnStatement stmt)
  {
    visit_graph_node (stmt, "ReturnStatement", {});
  }

  public override void visit_yield_statement (YieldStatement y)
  {
    visit_graph_node (y, "YieldStatement", {});
  }

  public override void visit_throw_statement (ThrowStatement stmt)
  {
    visit_graph_node (stmt, "ThrowStatement", {});
  }

  public override void visit_try_statement (TryStatement stmt)
  {
    visit_graph_node (stmt, "TryStatement", {});
  }

  public override void visit_catch_clause (CatchClause clause)
  {
    visit_graph_node (clause, "CatchClause",
                      {RecordEntry(){name="variable_name", value=clause.variable_name}});
  }

  public override void visit_lock_statement (LockStatement stmt)
  {
    visit_graph_node (stmt, "LockStatement", {});
  }

  public override void visit_delete_statement (DeleteStatement stmt)
  {
    visit_graph_node (stmt, "DeleteStatement", {});
  }

  public override void visit_expression (Expression expr)
  {
  }

  public override void visit_array_creation_expression (ArrayCreationExpression expr)
  {
    visit_graph_node (expr, "ArrayCreationExpression",
                      {RecordEntry(){name="rank", value=expr.rank.to_string()}});
  }

  public override void visit_boolean_literal (BooleanLiteral lit)
  {
    visit_graph_node (lit, "BooleanLiteral",
                      {RecordEntry(){name="value", value=lit.value.to_string()}});
  }

  public override void visit_character_literal (CharacterLiteral lit)
  {
    visit_graph_node (lit, "CharacterLiteral",
                      {RecordEntry(){name="value", value=lit.value}});
  }

  public override void visit_integer_literal (IntegerLiteral lit)
  {
    visit_graph_node (lit, "IntegerLiteral",
                      {RecordEntry(){name="value", value=lit.value}});
  }

  public override void visit_real_literal (RealLiteral lit)
  {
    visit_graph_node (lit, "RealLiteral",
                      {RecordEntry(){name="value", value=lit.value}});
  }

  public override void visit_string_literal (StringLiteral lit)
  {
    visit_graph_node (lit, "StringLiteral",
                      {RecordEntry(){name="value", value=lit.value}});
  }

  public override void visit_template (Template tmpl)
  {
    visit_graph_node (tmpl, "Template", {});
  }

  public override void visit_null_literal (NullLiteral lit)
  {
    visit_graph_node (lit, "NullLiteral", {});
  }

  public override void visit_member_access (MemberAccess expr)
  {
    visit_graph_node (expr, @"MemberAccess $(expr.member_name)", {});
  }

  public override void visit_method_call (MethodCall expr)
  {
    visit_graph_node (expr, "MethodCall",
                      {RecordEntry(){name="is_yield", value=expr.is_yield_expression.to_string()},
                       RecordEntry(){name="is_assert", value=expr.is_assert.to_string()}});
  }

  public override void visit_element_access (ElementAccess expr)
  {
    visit_graph_node (expr, "ElementAccess", {});
  }

  public override void visit_slice_expression (SliceExpression expr)
  {
    visit_graph_node (expr, "SliceExpression", {});
  }

  public override void visit_base_access (BaseAccess expr)
  {
    visit_graph_node (expr, "BaseAccess", {});
  }

  public override void visit_postfix_expression (PostfixExpression expr)
  {
    visit_graph_node (expr, "PostfixExpression",
                      {RecordEntry(){name="increment", value=expr.increment.to_string()}});
  }

  public override void visit_object_creation_expression (ObjectCreationExpression expr)
  {
    visit_graph_node (expr, "ObjectCreationExpression", {});
  }

  public override void visit_sizeof_expression (SizeofExpression expr)
  {
    visit_graph_node (expr, "SizeofExpression", {});
  }

  public override void visit_typeof_expression (TypeofExpression expr)
  {
    visit_graph_node (expr, "TypeofExpression", {});
  }

  public override void visit_unary_expression (UnaryExpression expr)
  {
    visit_graph_node (expr, "UnaryExpression", {});
  }

  public override void visit_cast_expression (CastExpression expr)
  {
    visit_graph_node (expr, "CastExpression", {});
  }

  public override void visit_named_argument (NamedArgument expr)
  {
    visit_graph_node (expr, "NamedArgument", {});
  }

  public override void visit_pointer_indirection (PointerIndirection expr)
  {
    visit_graph_node (expr, "PointerIndirection", {});
  }

  public override void visit_addressof_expression (AddressofExpression expr)
  {
    visit_graph_node (expr, "AddressofExpression", {});
  }

  public override void visit_reference_transfer_expression (ReferenceTransferExpression expr)
  {
    visit_graph_node (expr, "ReferenceTransferExpression", {});
  }

  public override void visit_binary_expression (BinaryExpression expr)
  {
    visit_graph_node (expr, "BinaryExpression",
                      {RecordEntry(){name="operator", value=expr.get_operator_string()}});
  }

  public override void visit_type_check (TypeCheck expr)
  {
    visit_graph_node (expr, "TypeCheck", {});
  }

  public override void visit_conditional_expression (ConditionalExpression expr)
  {
    visit_graph_node (expr, "ConditionalExpression", {});
  }

  public override void visit_lambda_expression (LambdaExpression expr)
  {
    visit_graph_node (expr, "LambdaExpression", {});
  }

  public override void visit_assignment (Assignment a)
  {
    visit_graph_node (a, "Assignment", {});
  }

  public override void visit_end_full_expression (Expression expr)
  {
    expr.accept (this);
  }
}
