defmodule Listerine.Commands do
  use Coxir.Commander

  @prefix "$"

  # PING COMMAND
  command ping do
    Message.reply(message, "pong!")
  end

  command study(roles) do
    case roles do
      [] ->
        Message.reply(message, "Usage: `study [course, ...]`")
      _ ->
        roles = String.upcase(roles)
        role_list = String.split(roles, " ")
        Listerine.Channels.role_list(message, role_list, :add)
    end
  end

  command unstudy(roles) do
    case roles do
      [] ->
        Message.reply(message, "Usage: `unstudy [course, ..]`")
      _ ->
        roles = String.upcase(roles)
        role_list = String.split(roles, " ")
        Listerine.Channels.role_list(message, role_list, :rm)
    end
  end

  # REVIEW: See if this bug has been patched
  @permit :BAN_MEMBERS
  command mkcourses(text) do
    [y | cl] =
      text
      |> String.split(" ")
      |> Enum.filter(fn x -> x != "" end)
      |> Enum.map(&String.upcase/1)

    cond do
      y in ["1", "2", "3"] ->
        case Listerine.Channels.add_courses(message.guild, y, cl) do
          [] -> Message.reply(message, "Didn't add any channels")
          cl -> Message.reply(message, "Added: #{unwords(cl)}")
        end

      true ->
        Message.reply(message, "Usage: `mkcourses [1,2,3] [course, ...]`")
    end
  end

  @permit :BAN_MEMBERS
  command rmcourses(text) do
    text =
      String.split(text, " ")
      |> Enum.filter(fn x -> x != "" end)
      |> Enum.map(&String.upcase/1)

    case Listerine.Channels.remove_courses(text) do
      [] -> Message.reply(message, "Didn't remove any channels")
      cl -> Message.reply(message, "Removed: #{unwords(cl)}")
    end
  end

  command mancourses() do
    embed = %{
      title: "Informação sobre as cadeiras disponíveis",
      color: 0xFF0000,
      footer: %{
        text: "Qualquer dúvida sobre o bot podes usar `$help` para saberes o que podes fazer."
      },
      description: "`$study CADEIRA` junta-te às salas das cadeiras
         `$study 1ano` junta-te a todas as cadeiras de um ano",
      fields: for(year <- 1..3, do: Listerine.Channels.generate_courses_embed_field(year))
    }

    Message.reply(message, embed: embed)
  end
  
  defp unwords(words), do: Enum.reduce(words, fn x, a -> a <> " " <> x end)
end
