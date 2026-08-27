# frozen_string_literal: true

require "rails_helper"

# These assert the *database* refuses bad data, not that a validation does.
# Principle III makes that distinction load-bearing: every check here bypasses
# Active Record validations deliberately, because the invariant is supposed to
# survive code that forgets to run them.
RSpec.describe "Schema constraints" do
  describe "links.code" do
    it "rejects a duplicate through the unique index, not through a prior lookup" do
      existing = create(:link)

      duplicate = build(:link, code: existing.code)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "rejects a code outside 3..32 characters" do
      expect { build(:link, code: "ab").save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /links_code_length_check/)
    end
  end

  describe "accounts.email" do
    it "treats addresses differing only in case as the same address" do
      create(:account, email: "Owner@Example.com")

      expect { build(:account, email: "owner@example.com").save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "check constraints" do
    it "rejects an unknown account role" do
      account = create(:account)

      expect { account.update_column(:role, "wizard") }
        .to raise_error(ActiveRecord::StatementInvalid, /accounts_role_check/)
    end

    it "rejects an unknown report status" do
      report = Report.create!(link: create(:link), status: "pending")

      expect { report.update_column(:status, "escalated") }
        .to raise_error(ActiveRecord::StatementInvalid, /reports_status_check/)
    end
  end

  # FR-024 / Principle V. Absent, not nullable-and-unused: a column that does
  # not exist cannot be populated by a careless later commit. This test is the
  # thing that fails when someone adds one.
  it "records nothing about the visitor on a click" do
    expect(Click.column_names).to contain_exactly("id", "link_id", "occurred_at")
  end
end
