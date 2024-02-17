require "armature"
require "uuid"
require "faker"

abstract struct TemplateFragment < Armature::Component
  private getter fragment_filter : Filter { Filter.new }

  def render_fragment(name : String, to io : IO)
    old_name = fragment_filter.name
    old_io = fragment_filter.io
    fragment_filter.name = name
    fragment_filter.io = io

    begin
      to_s fragment_filter
    ensure
      fragment_filter.name = old_name
      fragment_filter.io = old_io
    end
  end

  def fragment(name : String)
    old_fragment = fragment_filter.current_fragment
    fragment_filter.current_fragment = name
    begin
      yield
    ensure
      fragment_filter.current_fragment = old_fragment
    end
  end

  class Filter < IO
    property name : String?
    property io : IO?
    property current_fragment : String?

    def read(slice : Bytes)
      raise NotImplementedError.new("Can't read from an HTMLFragment::Template::Filter")
    end

    def write(slice : Bytes) : Nil
      if (io = @io) && (@current_fragment == @name)
        io.write slice
      end
    end
  end
end

class App
  include HTTP::Handler
  include Armature::Route

  def call(context)
    route context do |r, response, session|
      response.headers["content-type"] = "text/html"

      render "app/header" unless r.headers["HX-Request"]?

      r.root { response.redirect "/contacts" }
      r.on "contacts" { Contacts.new.call context }

      r.miss do
        response.status = :not_found
        render "app/not_found"
      end
    end
  end
end

struct Contacts
  include Armature::Route

  record Contact, id : UUID, name : String, archived_at : Time? = nil do
    def archived?
      !archived_at.nil?
    end

    def archive
      copy_with archived_at: Time.utc
    end

    def unarchive
      copy_with archived_at: nil
    end
  end

  ALL = Array
    .new(10) do
      Contact.new(
        id: UUID.random,
        name: Faker::Name.name,
      )
    end
    .index_by(&.id)

  def call(context)
    route context do |r, response, session|
      r.root do
        r.get do
          contacts = ALL.values
          render "contacts/list"
        end
      end

      r.on id: UUID do |id|
        if contact = ALL[id]?
          r.put do
            ALL[id] = contact.unarchive
            ContactRow.new(ALL[id]).render_fragment "button", to: response
          end

          r.delete do
            ALL[id] = contact.archive
            ContactRow.new(ALL[id]).render_fragment "button", to: response
          end
        end
      end
    end
  end

  record ContactRow < TemplateFragment, contact : Contact do
    def_to_s "contacts/row"
  end
end

log = Log.for("html_fragment_example")
http = HTTP::Server.new([
  HTTP::LogHandler.new(log),
  HTTP::CompressHandler.new,
  App.new,
])

signals = [:int, :term] of Signal
signals.each &.trap { http.close }

host = ENV.fetch("HOST", "127.0.0.1")
port = ENV.fetch("PORT", "3600").to_i
log.info &.emit "Listening for HTTP requests",
  host: host,
  port: port

http.listen host, port
