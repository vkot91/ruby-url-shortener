# frozen_string_literal: true

class CreateReports < ActiveRecord::Migration[8.0]
  def change
    create_table :reports, id: :uuid do |t|
      t.references :link, type: :uuid, null: false, foreign_key: true

      # Free text from the anonymous warning page. No reporter identity is
      # recorded anywhere on this row (FR-033, Principle V).
      t.text :reason
      t.text :status, null: false, default: "pending"

      t.references :reviewed_by, type: :uuid, null: true, foreign_key: { to_table: :accounts }
      t.datetime :reviewed_at

      t.datetime :created_at, null: false
    end

    # The moderation queue: pending first, oldest first (FR-033).
    add_index :reports, [ :status, :created_at ]

    add_check_constraint :reports,
                         "status IN ('pending', 'actioned', 'dismissed')",
                         name: "reports_status_check"
  end
end
