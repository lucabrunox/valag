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
        sub.create_node (@"node$((long)codenode)");
    }

    return (owned)graph;
  }

  private Gvc.Node find_node (void* obj)
  {
    return graph.find_node (@"node$((long)obj)");
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
        label.append (@" | { $(escape_gvlabel(entry.name)) | $(escape_gvlabel(entry.value)) }");
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
            if (is_weak)
              gedge.safe_set ("style", "dashed", "");
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

  private void visit_child (CodeNode? codenode, CodeNode? parent_node, string? label = null, bool is_weak = true)
  {
    if (codenode == null)
      return;

    var old_parent = this.parent_node;
    this.parent_node = parent_node;
    var old_weak = this.is_weak;
    this.is_weak = is_weak;
    var old_label = next_label;
    next_label = label;
    codenode.accept (this);
    next_label = old_label;
    this.is_weak = old_weak;
    this.parent_node = old_parent;
  }

  private string? get_label (CodeNode child)
  {
    string? label = null;
    if (child is DataType)
      {
        if (parent_node is Class)
          label = "base_class";
        else if (parent_node is Field)
          label = "field_type";
        else if (parent_node is LocalVariable)
          label = "variable_type";
        else if (parent_node is Method && ((Method)parent_node).return_type == child)
          label = "return_type";
        else if (parent_node is ObjectCreationExpression)
          label = "type_ref";
        else if (parent_node is FormalParameter)
          label = "param_type";
        else if (parent_node is Property)
          label = "prop_type";
        else if (parent_node is ForeachStatement)
          label = "type_ref";
        else if (parent_node is ArrayCreationExpression)
          label = "element_type";
        else if (parent_node is DataType)
          label = "type_arg";
      }
    else if ((parent_node is Field || parent_node is LocalVariable) && child is Expression)
      label = "initializer";
    else if (parent_node is SwitchStatement && child is Expression)
      label = "expression";
    else if (parent_node is Property && child == ((Property)parent_node).get_accessor)
      label = "get";
    else if (parent_node is Property && child == ((Property)parent_node).set_accessor)
      label = "set";
    else if (parent_node is IfStatement && child == ((IfStatement)parent_node).true_statement)
      label = "true";
    else if (parent_node is IfStatement && child == ((IfStatement)parent_node).false_statement)
      label = "false";
    else if ((parent_node is WhileStatement || parent_node is DoStatement) && child is Expression || (parent_node is ForStatement && ((ForStatement)parent_node).condition == child))
      label = "condition";
    else if (parent_node is TryStatement && ((TryStatement)parent_node).finally_body == child)
      label = "finally";
    else if (parent_node is MethodCall && ((MethodCall)parent_node).call == child)
      label = "call";
    else if (parent_node is ElementAccess && ((ElementAccess)parent_node).container == child)
      label = "container";
    else if (parent_node is SliceExpression)
      {
        var slice = (SliceExpression)parent_node;
        if (child == slice.container)
          label = "container";
        else if (child == slice.start)
          label = "start";
        else if (child == slice.stop)
          label = "stop";
      }

    return label;
  }

  // visitor

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
    visit_graph_node (cl, @"Class $(cl.get_full_name())",
                      {RecordEntry(){name="is_abstract", value=cl.is_abstract.to_string()},
                       RecordEntry(){name="is_compact", value=cl.is_compact.to_string()},
                       RecordEntry(){name="is_immutable", value=cl.is_immutable.to_string()}});
  }

  public override void visit_struct (Struct st)
  {
    visit_graph_node (st, @"Struct $(st.get_full_name())", {});
  }

  public override void visit_enum (Vala.Enum en)
  {
    visit_graph_node (en, @"Enum $(en.get_full_name())",
                      {RecordEntry(){name="is_flags", value=en.is_flags.to_string()}});
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
    visit_graph_node (d, @"Delegate $(d.name)",
                      {RecordEntry(){name="has_target", value=d.has_target.to_string()}});
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
    visit_graph_node (m, @"$(label) $(m.name)",
                      {RecordEntry(){name="is_abstract", value=m.is_abstract.to_string()},
                       RecordEntry(){name="is_virtual", value=m.is_virtual.to_string()},
                       RecordEntry(){name="overrides", value=m.overrides.to_string()},
                       RecordEntry(){name="closure", value=m.closure.to_string()},
                       RecordEntry(){name="coroutine", value=m.coroutine.to_string()}});
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
    visit_child (prop.field, prop, "field");
  }

  public override void visit_property_accessor (PropertyAccessor acc)
  {
    visit_graph_node (acc, "PropertyAccessor",
                      {RecordEntry(){name="automatic_body", value=acc.automatic_body.to_string()}});
  }

  public override void visit_signal (Vala.Signal sig)
  {
    var label = "Signal";
    if (sig is DynamicSignal)
      label = "DynamicSignal";
    visit_graph_node (sig, @"$(label) $(sig.name)",
                      {RecordEntry(){name="has_emitter", value=sig.has_emitter.to_string()},
                       RecordEntry(){name="is_virtual", value=sig.is_virtual.to_string()}});
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
    visit_child (ns.namespace_symbol, ns, "", false);
  }

  public override void visit_data_type (DataType type)
  {
    var label = "DataType";
    CodeNode? child = null;
    string? length = null;
    string? rank = null;

    if (type is DelegateType)
      {
        label = "DelegateType";
        child = ((DelegateType)type).delegate_symbol;
      }
    else if (type is FieldPrototype)
      {
        label = "FieldPrototype";
        child = ((FieldPrototype)type).field_symbol;
      }
    else if (type is GenericType)
      label = "GenericType";
    else if (type is InvalidType)
      label = "InvalidType";
    else if (type is MethodType)
      {
        label = "MethodType";
        child = ((MethodType)type).method_symbol;
      }
    else if (type is PointerType)
      label = "PointerType";
    else if (type is ArrayType)
      {
        label = "ArrayType";
        length = ((ArrayType)type).length.to_string ();
        rank = ((ArrayType)type).rank.to_string ();
      }
    else if (type is ClassType)
      {
        label = "ClassType";
        child = ((ClassType)type).class_symbol;
      }
    else if (type is SignalType)
      {
        label = "SignalType";
        child = ((SignalType)type).signal_symbol;
      }
    else if (type is Vala.ErrorType)
      label = "ErrorType";
    else if (type is InterfaceType)
      {
        label = "InterfaceType";
        child = ((InterfaceType)type).interface_symbol;
      }
    else if (type is NullType)
      label = "NullType";
    else if (type is ObjectType)
      {
        label = "ObjectType";
        child = ((ObjectType)type).type_symbol;
      }
    else if (type is UnresolvedType)
      label = "UnresolvedType";
    else if (type is VoidType)
      label = "VoidType";
    else if (type is ValueType)
      {
        child = ((ValueType)type).type_symbol;
        if (type is BooleanType)
          label = "BooleanType";
        else if (type is EnumValueType)
          label = "EnumValueType";
        else if (type is FloatingType)
          label = "FloatingType";
        else if (type is IntegerType)
          label = "IntegerType";
        else if (type is StructValueType)
          label = "StructValueType";
      }

    visit_graph_node (type, label,
                      {RecordEntry(){name="value_owned", value=type.value_owned.to_string()},
                       RecordEntry(){name="nullable", value=type.nullable.to_string()},
                       RecordEntry(){name="is_dynamic", value=type.is_dynamic.to_string()},
                       RecordEntry(){name="float_ref", value=type.floating_reference.to_string()},
                       RecordEntry(){name="length", value=length},
                       RecordEntry(){name="rank", value=rank}});
    visit_child (child, type, "");
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
    visit_graph_node (section, "SwitchSection",
                      {RecordEntry(){name="captured", value=section.captured.to_string()}});
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
    visit_child (expr.value_type, expr, "value_type");
    visit_child (expr.target_type, expr, "target_type");
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
    visit_graph_node (expr, "NamedArgument",
                      {RecordEntry(){name="name", value=expr.name}});
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
