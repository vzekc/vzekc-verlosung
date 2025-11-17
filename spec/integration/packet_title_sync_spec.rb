# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Packet Title Synchronization" do
  fab!(:user)
  fab!(:category)
  fab!(:lottery) do
    topic = Fabricate(:topic, category: category, user: user)
    Fabricate(:lottery, topic: topic)
  end
  fab!(:packet) do
    pkt = Fabricate(:lottery_packet, lottery_obj: lottery, ordinal: 1, title: "Original Title")
    # Set initial post content with title
    pkt.post.update!(raw: "# Paket 1: Original Title\n\nInitial description")
    pkt
  end

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    SiteSetting.vzekc_verlosung_category_id = category.id
  end

  describe "post editing title sync" do
    it "syncs packet title from post content to database when edited" do
      revisor = PostRevisor.new(packet.post)
      revisor.revise!(user, raw: "# Paket 1: Updated Title\n\nNew description")

      packet.reload
      expect(packet.title).to eq("Updated Title")
    end

    it "handles title with special characters" do
      revisor = PostRevisor.new(packet.post)
      revisor.revise!(user, raw: "# Paket 1: Commodore 64 & Accessories (Working!)\n\nDescription")

      packet.reload
      expect(packet.title).to eq("Commodore 64 & Accessories (Working!)")
    end

    it "does not sync if title is unchanged" do
      original_updated_at = packet.updated_at
      revisor = PostRevisor.new(packet.post)
      revisor.revise!(user, raw: "# Paket 1: Original Title\n\nAdded more description")

      packet.reload
      expect(packet.title).to eq("Original Title")
      # Updated_at shouldn't change if title didn't change
      expect(packet.updated_at.to_i).to eq(original_updated_at.to_i)
    end

    it "keeps original title if validation is bypassed and extraction fails" do
      # This test checks that if somehow validation is bypassed,
      # the original title is kept (sync hook can't extract title, logs warning)
      revisor = PostRevisor.new(packet.post)
      revisor.revise!(user, raw: "Just content without heading", skip_validations: true)

      packet.reload
      # Original title should be kept since extraction failed
      expect(packet.title).to eq("Original Title")
    end
  end

  describe "title removal validation" do
    it "prevents removing packet title when editing post" do
      revisor = PostRevisor.new(packet.post)
      result = revisor.revise!(user, raw: "Content without title heading")

      expect(result).to be false
      expect(packet.post.errors[:base]).to include(match(/Packet 1 title cannot be removed/))
    end

    it "allows editing post content while keeping title" do
      revisor = PostRevisor.new(packet.post)
      result =
        revisor.revise!(user, raw: "# Paket 1: Original Title\n\nUpdated description content")

      expect(result).to be true
      packet.reload
      expect(packet.title).to eq("Original Title")
    end

    it "allows changing title to a new title" do
      revisor = PostRevisor.new(packet.post)
      result = revisor.revise!(user, raw: "# Paket 1: New Title\n\nDescription")

      expect(result).to be true
      packet.reload
      expect(packet.title).to eq("New Title")
    end

    it "prevents changing packet ordinal number" do
      revisor = PostRevisor.new(packet.post)
      result = revisor.revise!(user, raw: "# Paket 5: Different Title\n\nDescription")

      expect(result).to be false
      expect(packet.post.errors[:base]).to include(match(/Expected.*Paket 1.*but found.*Paket 5/))
    end

    it "prevents titles shorter than 3 non-whitespace characters" do
      revisor = PostRevisor.new(packet.post)
      result = revisor.revise!(user, raw: "# Paket 1: AB\n\nDescription")

      expect(result).to be false
      expect(packet.post.errors[:base]).to include(match(/at least 3 non-whitespace characters/))
    end

    it "allows titles with exactly 3 non-whitespace characters" do
      revisor = PostRevisor.new(packet.post)
      result = revisor.revise!(user, raw: "# Paket 1: ABC\n\nDescription")

      expect(result).to be true
      packet.reload
      expect(packet.title).to eq("ABC")
    end

    it "counts only non-whitespace characters for length validation" do
      revisor = PostRevisor.new(packet.post)
      # "A B" has only 2 non-whitespace chars, should fail
      result = revisor.revise!(user, raw: "# Paket 1: A B\n\nDescription")

      expect(result).to be false
      expect(packet.post.errors[:base]).to include(match(/at least 3 non-whitespace characters/))
    end

    it "does not validate non-packet posts" do
      regular_post = Fabricate(:post, topic: packet.post.topic)
      revisor = PostRevisor.new(regular_post)
      result = revisor.revise!(user, raw: "Content without heading")

      expect(result).to be true
    end

    it "validates Abholerpaket title (ordinal 0)" do
      abholerpaket_post = Fabricate(:post, topic: lottery.topic, raw: "# Paket 0: Abholerpaket")
      abholerpaket =
        Fabricate(
          :lottery_packet,
          lottery_obj: lottery,
          post: abholerpaket_post,
          ordinal: 0,
          abholerpaket: true,
          title: "Abholerpaket",
        )

      revisor = PostRevisor.new(abholerpaket.post)
      result = revisor.revise!(user, raw: "Content without heading")

      expect(result).to be false
      expect(abholerpaket.post.errors[:base]).to include(match(/Packet 0 title cannot be removed/))
    end
  end

  describe "edge cases" do
    it "handles title with colon in content" do
      revisor = PostRevisor.new(packet.post)
      revisor.revise!(user, raw: "# Paket 1: GPU: NVIDIA RTX 3080\n\nDescription")

      packet.reload
      expect(packet.title).to eq("GPU: NVIDIA RTX 3080")
    end

    it "handles empty title after colon (keeps original)" do
      # This test checks that if validation is bypassed and title is empty after colon,
      # the original title is kept (sync hook can't extract valid title, logs warning)
      revisor = PostRevisor.new(packet.post)
      revisor.revise!(user, raw: "# Paket 1: \n\nDescription", skip_validations: true)

      packet.reload
      expect(packet.title).to eq("Original Title") # Keeps original
    end

    it "syncs title when editing newly created post" do
      # Create a new packet with a post
      new_packet =
        Fabricate(:lottery_packet, lottery_obj: lottery, ordinal: 2, title: "Initial Title")
      new_packet.post.update!(raw: "# Paket 2: Initial Title\n\nDescription")

      # Edit the post
      revisor = PostRevisor.new(new_packet.post)
      revisor.revise!(user, raw: "# Paket 2: Changed Title\n\nDescription")

      new_packet.reload
      expect(new_packet.title).to eq("Changed Title")
    end
  end
end
