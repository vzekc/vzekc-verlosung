# frozen_string_literal: true

require "rails_helper"

RSpec.describe VzekcVerlosung::TitleExtractor do
  describe ".extract_title" do
    it "extracts title from packet post markdown" do
      raw = "# Paket 1: GPU Bundle\n\nDescription..."
      expect(described_class.extract_title(raw)).to eq("GPU Bundle")
    end

    it "extracts title with special characters" do
      raw = "# Paket 5: Commodore 64 & Peripherals (Working!)\n\nGreat condition"
      expect(described_class.extract_title(raw)).to eq("Commodore 64 & Peripherals (Working!)")
    end

    it "handles title with trailing whitespace" do
      raw = "# Paket 10: Network Cards   \n\nDescription"
      expect(described_class.extract_title(raw)).to eq("Network Cards")
    end

    it "returns nil for missing title" do
      raw = "Just some content without a heading"
      expect(described_class.extract_title(raw)).to be_nil
    end

    it "returns nil for empty string" do
      expect(described_class.extract_title("")).to be_nil
    end

    it "returns nil for nil input" do
      expect(described_class.extract_title(nil)).to be_nil
    end

    it "extracts title from Abholerpaket (ordinal 0)" do
      raw = "# Paket 0: System für mich\n\nDescription"
      expect(described_class.extract_title(raw)).to eq("System für mich")
    end

    it "extracts title from multi-line content" do
      raw = "# Paket 3: Complete Setup\n\nThis is a long\nmulti-line description"
      expect(described_class.extract_title(raw)).to eq("Complete Setup")
    end
  end

  describe ".extract_packet_number" do
    it "extracts packet number from markdown" do
      raw = "# Paket 5: GPU Bundle"
      expect(described_class.extract_packet_number(raw)).to eq(5)
    end

    it "extracts ordinal 0 for Abholerpaket" do
      raw = "# Paket 0: Abholerpaket"
      expect(described_class.extract_packet_number(raw)).to eq(0)
    end

    it "returns nil for missing packet heading" do
      raw = "Just content"
      expect(described_class.extract_packet_number(raw)).to be_nil
    end

    it "returns nil for empty string" do
      expect(described_class.extract_packet_number("")).to be_nil
    end
  end

  describe ".has_title?" do
    it "returns true when title exists" do
      raw = "# Paket 1: GPU Bundle"
      expect(described_class.has_title?(raw)).to be true
    end

    it "returns false when title is missing" do
      raw = "Just content without heading"
      expect(described_class.has_title?(raw)).to be false
    end

    it "returns false for empty string" do
      expect(described_class.has_title?("")).to be false
    end

    it "returns false for nil" do
      expect(described_class.has_title?(nil)).to be false
    end

    it "returns true for Abholerpaket" do
      raw = "# Paket 0: Abholerpaket"
      expect(described_class.has_title?(raw)).to be true
    end
  end

  describe ".extract_abholerpaket_title" do
    it "extracts Abholerpaket title (ordinal 0)" do
      raw = "# Paket 0: System für mich"
      expect(described_class.extract_abholerpaket_title(raw)).to eq("System für mich")
    end

    it "returns nil for regular packet" do
      raw = "# Paket 5: GPU Bundle"
      expect(described_class.extract_abholerpaket_title(raw)).to be_nil
    end

    it "returns nil for missing heading" do
      raw = "Just content"
      expect(described_class.extract_abholerpaket_title(raw)).to be_nil
    end
  end
end
