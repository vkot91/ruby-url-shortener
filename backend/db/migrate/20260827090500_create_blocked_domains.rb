# frozen_string_literal: true

class CreateBlockedDomains < ActiveRecord::Migration[8.0]
  def change
    create_table :blocked_domains, id: :uuid do |t|
      # citext for the same reason as accounts.email: hostnames are
      # case-insensitive, so the column says so.
      t.citext :domain, null: false
      t.text :reason
      t.references :created_by, type: :uuid, null: true, foreign_key: { to_table: :accounts }

      t.datetime :created_at, null: false
    end

    add_index :blocked_domains, :domain, unique: true
  end
end
