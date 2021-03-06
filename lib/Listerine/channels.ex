defmodule Listerine.Channels do
  @moduledoc """
  This module provides functions to create and remove private channels.
  """

  use Coxir

  # Reads the channels from the config.json file.
  defp get_courses() do
    case File.read("config.json") do
      {:ok, ""} -> nil
      {:ok, body} -> Poison.decode!(body)["courses"]
      _ -> nil
    end
  end
  # Updates the config.json with the new courses.
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
  Generates an array with embed fields that contain all available courses.
  """
  def generate_courses_embed_fields() do
    possible_embed_fiels =
      for(year <- Map.keys(get_courses()), do: generate_courses_embed_field(year))

    Enum.filter(possible_embed_fiels, fn x -> Map.get(x, :value) != "" end)
  end

  # Generates a Formated field to use in embed with all courses in the given year.
  defp generate_courses_embed_field(year) do
    %{
      name: year <> "º ano",
      value: get_courses_year(year),
      inline: true
    }
  end

  # Generates a string with all the courses in a year separated by a newline.
  defp get_courses_year(year) do
    courses_year_arr = Map.keys(Map.get(get_courses(), year))
    Enum.join(courses_year_arr, "\n")
  end

  @doc """
  Adds courses to the guild and registers them to the config.json file.

  Returns the list of added courses or `nil` if none were added.
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

  # Creates the private channels, corresponding roles and sets the permissions.
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
    ch2 = Guild.create_channel(guild, %{name: "anexos", type: 0, parent_id: cat.id})

    Map.put(create_course_channels(guild, others), cat.name, %{
      "role" => role.id,
      "channels" => [cat.id, ch1.id, ch2.id]
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
        # Only let registered channels be deleted.
        valid_courses =
          map
          |> Map.values()
          |> Enum.reduce([], fn x, acc -> acc ++ Map.keys(x) end)
          |> Listerine.Helpers.intersect(courses)

        removed =
          map
          |> Map.values()
          |> Enum.reduce(
            [],
            fn x, ac -> ac ++ (Map.take(x, valid_courses) |> Map.values()) end
          )
          |> remove_course_channels()

        new_map =
          Enum.reduce(Map.keys(map), map, fn x, acc ->
            Map.put(acc, x, Map.drop(map[x], valid_courses))
          end)

        save_courses(new_map)

        removed
    end
  end

  # Removes the channels and roles from the guild.
  defp remove_course_channels([]), do: []

  defp remove_course_channels([course | others]) do
    do_or_nil = fn
      nil, _ -> nil
      x, f -> f.(x)
    end

    Role.get(course["role"]) |> do_or_nil.(&Role.delete/1)
    prepend = fn x, l -> [x | l] end

    course["channels"]
    |> Enum.reduce(
      [],
      fn c, ac -> [Channel.get(c) |> do_or_nil.(&Channel.delete/1) | ac] end
    )
    |> (fn
          nil -> nil
          a -> Enum.find(a, fn x -> x.type == 4 end).name
        end).()
    |> prepend.(remove_course_channels(others))
  end

  @doc """
  Adds the roles passed in the `courses` list the the author of the `message`.

  Returns a list of added roles.
  """
  def add_roles(message, courses) do
    guild = message.channel.guild_id
    member = Guild.get_member(guild, message.author.id)

    case get_courses() do
      nil ->
        nil

      roles ->
        roles = Enum.reduce(Map.keys(roles), %{}, fn x, acc -> Map.merge(acc, roles[x]) end)

        Enum.filter(courses, fn x -> x in Map.keys(roles) end)
        |> Enum.reduce([], fn x, acc ->
          case Member.add_role(member, roles[x]["role"]) do
            :ok -> [x | acc]
            _ -> acc
          end
        end)
    end
  end

  def get_roles_year(year) do
    Map.keys(get_courses()[year])
  end

  @doc """
  Removes the roles passed in the `courses` list the the author of the `message`.

  Returns a list of removed roles.
  """
  def rm_role(message, courses) do
    guild = message.channel.guild_id
    member = Guild.get_member(guild, message.author.id)

    case get_courses() do
      nil ->
        nil

      roles ->
        roles = Enum.reduce(Map.keys(roles), %{}, fn x, acc -> Map.merge(acc, roles[x]) end)

        Enum.filter(courses, fn x -> x in Map.keys(roles) end)
        |> Enum.reduce([], fn x, acc ->
          case Member.remove_role(member, roles[x]["role"]) do
            :ok -> [x | acc]
            _ -> acc
          end
        end)
    end
  end
end
