# frozen_string_literal: true

class CreateRefreshTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :refresh_tokens do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }

      # Opaque random bytes, not a JWT, and only ever stored hashed. Nothing
      # about a refresh token benefits from being self-describing, and an opaque
      # one cannot leak claims to whoever ends up holding it.
      t.text :token_digest, null: false

      # One sign-in produces one family. Rotation issues a successor inside the
      # same family; detecting a replay revokes the family as a unit, which is
      # the whole point of tracking it.
      t.uuid :family_id, null: false

      # Set when the token is exchanged. A token presented with this already set
      # is a replay: either the client repeated itself or someone else has a
      # copy, and both answers are "revoke the family".
      t.datetime :used_at

      t.datetime :expires_at, null: false
      t.datetime :revoked_at

      # The account holder's own client at sign-in. Principle V governs the
      # anonymous redirect path, not a session the holder can inspect and
      # revoke.
      t.text :user_agent
      t.text :ip_address

      t.datetime :created_at, null: false
    end

    add_index :refresh_tokens, :token_digest, unique: true

    # Revoking a family, and revoking every family of a banned account, are both
    # single-index operations.
    add_index :refresh_tokens, :family_id
  end
end
