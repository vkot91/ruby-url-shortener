# frozen_string_literal: true

class CreateLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :links do |t|
      t.references :account, null: false, foreign_key: true

      t.text :code, null: false
      t.text :destination_url, null: false
      t.text :name

      # Denormalised, maintained by the batch flush job. It survives the 7-day
      # clicks purge, so a creator's lifetime total is not a function of
      # retention.
      t.bigint :clicks_count, null: false, default: 0

      t.datetime :banned_at   # FR-031
      t.datetime :deleted_at  # soft delete, FR-028

      t.timestamps
    end

    # This constraint IS the code-allocation algorithm (Principle III, D3).
    # Nothing queries for a code's existence before inserting; the insert is
    # attempted and the violation is caught.
    add_index :links, :code, unique: true

    # The dashboard list query, and only that query — partial on the soft-delete
    # flag so deleted rows carry no index weight.
    add_index :links, [ :account_id, :created_at ],
              order: { created_at: :desc },
              where: "deleted_at IS NULL",
              name: "index_links_on_account_id_and_created_at_active"

    # Admin search by destination (FR-030). Trigram rather than btree because
    # the admin searches by substring, not by prefix.
    add_index :links, :destination_url, using: :gin, opclass: :gin_trgm_ops,
              name: "index_links_on_destination_url_trgm"

    add_check_constraint :links, "length(code) BETWEEN 3 AND 32", name: "links_code_length_check"
  end
end
