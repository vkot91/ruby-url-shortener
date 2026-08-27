# frozen_string_literal: true

class CreateAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      # citext, not a lowercasing callback: case-insensitive uniqueness is a
      # property of the data, so the column type enforces it (Principle III).
      t.citext :email, null: false
      t.text :password_digest, null: false
      t.text :role, null: false, default: "creator"

      # Only `free` exists in the MVP. The column and its check constraint are
      # here so introducing a paid tier is a constraint change rather than a
      # migration against a live table.
      t.text :plan, null: false, default: "free"

      # NULL means active (FR-031).
      t.datetime :banned_at

      t.timestamps
    end

    add_index :accounts, :email, unique: true

    add_check_constraint :accounts, "role IN ('creator', 'admin')", name: "accounts_role_check"
    add_check_constraint :accounts, "plan IN ('free')", name: "accounts_plan_check"
  end
end
