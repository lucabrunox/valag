/*
    Copyright © 2010 Luca Bruno

    This file is part of Valag.

    Valag is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Valag is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public License
    along with libfreespeak.  If not, see <http://www.gnu.org/licenses/>.
*/

using Vala;
using Gvc;

public class Valag.GraphEdge
{
  public Gvc.Node from;
  public Gvc.Node to;
  public string? label = null;

  public uint hash ()
  {
    return (uint)(long)from + (uint)(long)to + (label == null ? 0 : label.hash());
  }

  public bool equal (void* obj)
  {
    var edge = (Valag.GraphEdge)obj;
    return edge.from == from && edge.to == to && edge.label == label;
  }
}

public class Valag.GraphGenerator : CodeVisitor
{
  private GraphContext context;
  private Graph graph; 
  private void* parent_node = null;
  private bool is_weak = false;
  private string? next_label = null;
  private int rank = 0;
  private Vala.List<Vala.List<CodeNode>> ranking = new ArrayList<Vala.List<CodeNode>> ();
  private Set<GraphEdge> edges = new HashSet<GraphEdge>((HashFunc)GraphEdge.hash, (EqualFunc)GraphEdge.equal);

  public GraphGenerator (string graph_name)
    {
      graph = new Graph (graph_name, GraphKind.AGDIGRAPH);
    }
  
  private struct RecordEntry
  {
    public string name;
    public string? value;
  }

  /**
   * Generate a graphviz dot file in the specified context.
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
    assert (rank == 0);

    /* use subgraphs to enforce rank */
    foreach (var rankset in ranking)
    {
      unowned Graph sub = graph.create_subgraph (@"sub$((long)rankset)");
      sub.safe_set ("rank", "same", "");
      foreach (var codenode in rankset)
      {
        if (codenode is Symbol)
          stdout.printf("%d %s\n", ranking.index_of (rankset), (codenode as Symbol).name);
        sub.create_node (@"node$((long)codenode)");
      }
    }

    return (owned)graph;
  }

  private Gvc.Node find_node (void* obj)
  {
    return graph.find_node (@"node$((long)obj)");
  }

  private Gvc.Node create_node (void* obj, string? name, RecordEntry[] entries)
  {
    var node_name = @"node$((long)obj)";
    var node = graph.find_node (node_name);
    if (node != null)
      return node;

    node = graph.create_node (node_name);
    if (obj is TypeSymbol)
      node.safe_set ("shape", "Mrecord", "");
    else
      node.safe_set ("shape", "record", "");

    var label = new StringBuilder();
    label.append (@"{ $(name)");
    foreach (weak RecordEntry entry in entries)
    {
      if (entry.value != null && entry.value != "false")
        label.append (@" | { $(entry.name) | $(entry.value) }");
    }
    label.append (" }");
    node.safe_set ("label", label.str, "");

    return (owned)node;
  }

  private Gvc.Node visit_graph_node (CodeNode codenode, string? name, RecordEntry[] entries)
  {
    var node = create_node (codenode, name, entries);
    if (parent_node != null)
      {
        var edge = new GraphEdge ();
        edge.from = find_node (parent_node);
        edge.to = node;
        edge.label = next_label ?? get_label (codenode);
        if (!(edge in edges))
          {
            var gedge = graph.create_edge (find_node (parent_node), node);
            if (edge.label != null)
              {
                gedge.safe_set ("label", edge.label, "");
                gedge.safe_set ("fontsize", "8", "");
              }
            edges.add (edge);
          }
      }

    if (!is_weak)
      {
        // higher rank
        var cur_rank = node["rank"];
        if (cur_rank != null && rank > cur_rank.to_int())
          ranking[cur_rank.to_int()].remove (codenode);
        else
          {
            // add to rank
            if (rank >= ranking.size)
              ranking.add (new ArrayList<CodeNode>());
            ranking[rank].add (codenode);
            node.safe_set ("rank", rank.to_string(), "");
          }
        rank++;
        var old_parent = parent_node;
        parent_node = codenode;
        codenode.accept_children (this);
        parent_node = old_parent;
        rank--;
      }
    
    return node;
  }

  private void visit_weak (CodeNode? codenode, CodeNode? parent_node, string? label = null)
  {
    if (codenode == null)
      return;

    var old_parent = this.parent_node;
    this.parent_node = parent_node;
    var old_weak = is_weak;
    is_weak = true;
    var old_label = next_label;
    next_label = label;
    codenode.accept (this);
    next_label = old_label;
    is_weak = old_weak;
    this.parent_node = old_parent;
  }

  private string? get_label (CodeNode child)
  {
    string? label = null;
    if (child is DataType)
      {
        if (parent_node is Field)
          label = "field_type";
        else if (parent_node is LocalVariable)
          label = "variable_type";
        else if (parent_node is Method)
          label = "return_type";
        else if (parent_node is ObjectCreationExpression)
          label = "type_ref";
      }
    else if ((parent_node is Field || parent_node is LocalVariable) && child is Expression)
      label = "initializer";
    else if (parent_node is SwitchStatement && child is Expression)
      label = "expression";

    return label;
  }

  public override void visit_source_file (SourceFile source_file)
  {
    create_node (source_file, "SourceFile",
                 {RecordEntry() {name="filename", value=source_file.filename}});
    var old_parent = parent_node;
    parent_node = source_file;
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
    visit_graph_node (edomain, "ErrorDomain", {});
  }

  public override void visit_error_code (ErrorCode ecode)
  {
    visit_graph_node (ecode, "ErrorCode", {});
  }

  public override void visit_delegate (Delegate d)
  {
    visit_graph_node (d, "Delegate", {});
  }

  public override void visit_member (Member m)
  {
    visit_graph_node (m, @"Member $(m.name)", {});
  }

  public override void visit_constant (Constant c)
  {
    visit_graph_node (c, "Constant",
                      {RecordEntry() {name="name", value=c.name}});
  }

  public override void visit_field (Field f)
  {
    visit_graph_node (f, "Field",
                      {RecordEntry() {name="name", value=f.name}});
  }

  public override void visit_method (Method m)
  {
    visit_graph_node (m, "Method",
                      {RecordEntry() {name="name", value=m.name}});
  }

  public override void visit_creation_method (CreationMethod m)
  {
    visit_graph_node (m, "CreationMethod",
                      {RecordEntry(){name="name", value=m.name}});
  }

  public override void visit_formal_parameter (FormalParameter p)
  {
    visit_graph_node (p, "FormalParameter",
                      {RecordEntry() {name="name", value=p.name}});
  }

  public override void visit_property (Property prop)
  {
    visit_graph_node (prop, "Property", {});
  }

  public override void visit_property_accessor (PropertyAccessor acc)
  {
    visit_graph_node (acc, "PropertyAccessor", {});
  }

  public override void visit_signal (Vala.Signal sig)
  {
    visit_graph_node (sig, "Signal", {});
  }

  public override void visit_constructor (Constructor c)
  {
    visit_graph_node (c, "Constructor", {});
  }

  public override void visit_destructor (Destructor d)
  {
    visit_graph_node (d, "Destructor", {});
  }

  public override void visit_type_parameter (TypeParameter p)
  {
    visit_graph_node (p, "TypeParameter", {});
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
    visit_weak (type.data_type, type, "");
  }
  
  public override void visit_block (Block b)
  {
    visit_graph_node (b, "Block", {});
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
    visit_graph_node (local, "LocalVariable",
                      {RecordEntry(){name="name", value=local.name}});
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
    visit_graph_node (stmt, "ForeachStatement", {});
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
    visit_graph_node (clause, "CatchClause", {});
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
    visit_weak (expr.value_type, expr, "value_type");
    visit_weak (expr.target_type, expr, "target_type");
  }

  public override void visit_array_creation_expression (ArrayCreationExpression expr)
  {
    visit_graph_node (expr, "ArrayCreationExpression", {});
  }

  public override void visit_boolean_literal (BooleanLiteral lit)
  {
    visit_graph_node (lit, "BooleanLiteral", {});
  }

  public override void visit_character_literal (CharacterLiteral lit)
  {
    visit_graph_node (lit, "CharacterLiteral", {});
  }

  public override void visit_integer_literal (IntegerLiteral lit)
  {
    visit_graph_node (lit, "IntegerLiteral",
                      {RecordEntry(){name="value", value=lit.value}});
  }

  public override void visit_real_literal (RealLiteral lit)
  {
    visit_graph_node (lit, "RealLiteral", {});
  }

  public override void visit_string_literal (StringLiteral lit)
  {
    visit_graph_node (lit, "StringLiteral", {});
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
    visit_graph_node (expr, "MemberAccess",
                      {RecordEntry(){name="name", value=expr.member_name}});
  }

  public override void visit_method_call (MethodCall expr)
  {
    visit_graph_node (expr, "MethodCall", {});
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
    visit_graph_node (expr, "EndFullExpression", {});
  }
}