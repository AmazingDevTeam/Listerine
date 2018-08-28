defmodule Listerine.Channels do
  @moduledoc """
  This module provides functions to create and remove private channels
  """

  use Coxir

  # Decodes the config.json file
  defp get_courses() do
    case File.read("config.json") do
      {:ok, ""} -> nil
      {:ok, body} -> Poison.decode!(body)["courses"]
      _ -> nil
    end
  end

  defp save_courses(courses) do
    new_map =
      case File.read("config.json") do
        {:ok, ""} ->
          %{"courses" => courses}

        {:ok, body} ->
          map = Poison.decode!(body)
          Map.put(map, "courses", courses)

        _ ->
          %{"courses" => courses}
      end

    File.write("config.json", Poison.encode!(new_map), [:binary])
  end

  @doc """
  Adds courses to the guild and registers them to the config.json file
  """
  def add_courses(guild, year, courses) do
    courses = Enum.uniq(courses)
    map_zeros = fn x -> Map.new(x, fn e -> {e, %{"role" => 0, "channels" => []}} end) end

    {courses, new_map} =
      case get_courses() do
        nil ->
          {courses, %{year => map_zeros.(courses)}}

        map ->
          case map[year] do
            nil -> {courses, put_in(map[year], map_zeros.(courses))}
            crs -> {courses -- Map.keys(crs), map}
          end
      end

    added = create_course_channels(guild, courses)
    new_map = update_in(new_map[year], fn cl -> Map.merge(cl, added) end)

    save_courses(new_map)

    Map.keys(added)
  end

  # Creates the private channels, corresponding roles and sets the permissions
  defp create_course_channels(_, []), do: %{}

  defp create_course_channels(guild, [course | others]) do
    role =
      Guild.create_role(
        guild,
        %{:name => course, :hoist => false, :mentionable => true}
      )

    ow = [
      %{id: get_role(Guild.get_roles(guild), "@everyone").id, type: "role", deny: 1024},
      %{id: role.id, type: "role", allow: 1024}
    ]

    cat = Guild.create_channel(guild, %{name: course, type: 4, permission_overwrites: ow})
    ch1 = Guild.create_channel(guild, %{name: "duvidas", type: 0, parent_id: cat.id})

    Map.put(create_course_channels(guild, others), cat.name, %{
      "role" => role.id,
      "channels" => [cat.id, ch1.id]
    })
  end

  # Returns a role with a given name or `nil` if none are found.
  defp get_role(l, name), do: Enum.find(l, fn e -> e[:name] == name end)

  @doc """
  Removes courses from the config.json file and the corresponding channels and roles
  from the guild.

  Returns the list of removed channels or `nil` if none where removed.
  """
  def remove_courses(courses) do
    case get_courses() do
      nil ->
        nil

      map ->
        # Only let registered channels be deleted
        courses =
          map
          |> Map.values()
          |> Enum.reduce([], fn x, acc -> acc ++ Map.keys(x) end)
          |> Listerine.Helpers.intersect(courses)

        removed =
          map
          |> Map.values()
          |> Enum.reduce([], fn x, ac -> ac ++ (Map.take(x, courses) |> Map.values()) end)
          |> remove_course_channels()

        new_map =
          Enum.reduce(Map.keys(map), map, fn x, acc ->
            Map.put(acc, x, Map.drop(map[x], courses))
          end)

        save_courses(new_map)

        removed
    end
  end

  # Removes the channels and roles from the guild
  defp remove_course_channels([]), do: []

  defp remove_course_channels([course | others]) do
    monad = fn
      nil, _ -> nil
      x, f -> f.(x)
    end

    Role.get(course["role"]) |> monad.(&Role.delete/1)
    prepend = fn x, l -> [x | l] end

    course["channels"]
    |> Enum.reduce([], fn c, ac -> [Channel.get(c) |> monad.(&Channel.delete/1) | ac] end)
    |> (fn
          nil -> nil
          a -> Enum.find(a, fn x -> x.type == 4 end).name
        end).()
    |> prepend.(remove_course_channels(others))
  end
end