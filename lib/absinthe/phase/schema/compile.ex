defmodule Absinthe.Phase.Schema.Compile do
  @moduledoc false

  alias Absinthe.Blueprint.Schema

  def run(blueprint, opts) do
    module_name = Module.concat(opts[:module], Compiled)

    %{schema_definitions: [schema]} = blueprint

    type_ast = build_types(schema.type_artifacts)
    directive_ast = build_directives(schema.directive_artifacts)

    type_list =
      Map.new(schema.type_definitions, fn type_def ->
        {type_def.identifier, type_def.name}
      end)

    directive_list =
      Map.new(schema.directive_definitions, fn type_def ->
        {type_def.identifier, type_def.name}
      end)

    metadata = build_metadata(schema)

    implementors = build_implementors(schema)

    body = [
      type_ast,
      directive_ast,
      quote do
        def __absinthe_types__ do
          unquote(Macro.escape(type_list))
        end

        def __absinthe_directives__() do
          unquote(Macro.escape(directive_list))
        end

        def __absinthe_interface_implementors__() do
          unquote(Macro.escape(implementors))
        end
      end,
      metadata
    ]

    Module.create(module_name, body, Macro.Env.location(__ENV__))

    {:ok, blueprint}
  end

  def build_metadata(schema) do
    for type <- schema.type_definitions do
      quote do
        def __absinthe_reference__(unquote(type.identifier)) do
          unquote(Macro.escape(type.__reference__))
        end
      end
    end
  end

  def build_types(types) do
    for type <- types do
      if !type.definition,
        do:
          raise("""
          No definition set!
          #{inspect(type)}
          """)

      ast = Macro.escape(type, unquote: true)

      quote do
        def __absinthe_type__(unquote(type.identifier)) do
          unquote(ast)
        end

        def __absinthe_type__(unquote(type.name)) do
          unquote(ast)
        end
      end
    end
    |> Enum.concat([
      quote do
        def __absinthe_type__(_type) do
          nil
        end
      end
    ])
  end

  def build_directives(directives) do
    for type <- directives do
      ast = Macro.escape(type)

      quote do
        def __absinthe_directive__(unquote(type.identifier)) do
          unquote(ast)
        end

        def __absinthe_directive__(unquote(type.name)) do
          unquote(ast)
        end
      end
    end
    |> Enum.concat([
      quote do
        def __absinthe_directive__(_type) do
          nil
        end
      end
    ])
  end

  defp build_implementors(schema) do
    schema.type_definitions
    |> Enum.filter(&match?(%Schema.InterfaceTypeDefinition{}, &1))
    |> Map.new(fn iface ->
      implementors =
        for %Schema.ObjectTypeDefinition{} = obj <- schema.type_definitions,
            iface.identifier in obj.interfaces,
            do: obj.identifier

      {iface.identifier, Enum.sort(implementors)}
    end)
  end
end
