# frozen_string_literal: true

# data-model.md specifies timestamptz for every timestamp column. Rails 7+
# defaults `datetime` to `timestamp without time zone`, which silently discards
# the offset on any value that arrives with one. Setting it once here keeps
# `t.datetime` and `t.timestamps` honest across every migration.
ActiveSupport.on_load(:active_record_postgresqladapter) do
  self.datetime_type = :timestamptz
end
