# frozen_string_literal: true

require "rails_helper"

RSpec.describe VzekcVerlosung::JavascriptLotteryDrawer do
  describe ".draw" do
    let(:input) do
      {
        "title" => "Test Lottery",
        "timestamp" => "2024-01-01T00:00:00Z",
        "packets" => [
          {
            "id" => 1,
            "title" => "Hardware Bundle",
            "participants" => [
              { "name" => "alice", "tickets" => 2 },
              { "name" => "bob", "tickets" => 1 },
              { "name" => "charlie", "tickets" => 1 },
            ],
          },
          {
            "id" => 2,
            "title" => "Software Bundle",
            "participants" => [
              { "name" => "alice", "tickets" => 1 },
              { "name" => "bob", "tickets" => 2 },
            ],
          },
        ],
      }
    end

    it "returns a valid result structure" do
      result = described_class.draw(input)

      expect(result).to be_a(Hash)
      expect(result["title"]).to eq("Test Lottery")
      expect(result["timestamp"]).to eq("2024-01-01T00:00:00Z")
      expect(result["rngSeed"]).to be_a(String)
      expect(result["drawingTimestamp"]).to be_a(String)
      expect(result["packets"]).to eq(input["packets"])
      expect(result["drawings"]).to be_an(Array)
      expect(result["drawings"].length).to eq(2)
    end

    it "includes correct drawing details" do
      result = described_class.draw(input)
      first_drawing = result["drawings"][0]

      expect(first_drawing["text"]).to eq("Hardware Bundle")
      expect(first_drawing["winners"]).to be_an(Array)
      expect(first_drawing["winners"].length).to eq(1)
      expect(first_drawing["winners"][0]).to be_in(%w[alice bob charlie])
      expect(first_drawing["participants"]).to be_an(Array)
      expect(first_drawing["participants"].length).to eq(3)
    end

    it "produces deterministic results with same input" do
      result1 = described_class.draw(input)
      result2 = described_class.draw(input)

      expect(result1["rngSeed"]).to eq(result2["rngSeed"])
      expect(result1["drawings"]).to eq(result2["drawings"])
    end

    it "produces different results with different timestamps" do
      input2 = input.merge("timestamp" => "2024-01-02T00:00:00Z")

      result1 = described_class.draw(input)
      result2 = described_class.draw(input2)

      expect(result1["rngSeed"]).not_to eq(result2["rngSeed"])
    end

    it "produces different results with different participants" do
      input2 = input.dup
      input2["packets"] = input2["packets"].dup
      input2["packets"][0] = input2["packets"][0].merge(
        "participants" => [{ "name" => "dave", "tickets" => 1 }],
      )

      result1 = described_class.draw(input)
      result2 = described_class.draw(input2)

      expect(result1["rngSeed"]).not_to eq(result2["rngSeed"])
    end

    it "handles single participant" do
      single_input = {
        "title" => "Single Winner",
        "timestamp" => "2024-01-01T00:00:00Z",
        "packets" => [
          {
            "id" => 1,
            "title" => "Prize",
            "participants" => [{ "name" => "alice", "tickets" => 1 }],
          },
        ],
      }

      result = described_class.draw(single_input)
      expect(result["drawings"][0]["winners"]).to eq(["alice"])
    end

    it "handles multiple tickets per participant" do
      multi_ticket_input = {
        "title" => "Multi Ticket",
        "timestamp" => "2024-01-01T00:00:00Z",
        "packets" => [
          {
            "id" => 1,
            "title" => "Prize",
            "participants" => [
              { "name" => "alice", "tickets" => 100 },
              { "name" => "bob", "tickets" => 1 },
            ],
          },
        ],
      }

      # Run multiple times to check probability
      winners =
        10.times.map { described_class.draw(multi_ticket_input)["drawings"][0]["winners"][0] }

      # Alice should win significantly more often (but not guaranteed every time)
      alice_wins = winners.count("alice")
      expect(alice_wins).to be > 5 # At least half with 100:1 odds
    end

    it "respects timeout limit" do
      # Create input with many participants to slow down execution
      large_input = {
        "title" => "Large Lottery",
        "timestamp" => "2024-01-01T00:00:00Z",
        "packets" => [
          {
            "id" => 1,
            "title" => "Prize",
            "participants" => 1000.times.map { |i| { "name" => "user#{i}", "tickets" => 1 } },
          },
        ],
      }

      # Should still complete within timeout (5 seconds)
      expect { described_class.draw(large_input) }.not_to raise_error
    end

    it "handles empty participants gracefully" do
      empty_input = {
        "title" => "Empty",
        "timestamp" => "2024-01-01T00:00:00Z",
        "packets" => [{ "id" => 1, "title" => "Prize", "participants" => [] }],
      }

      result = described_class.draw(empty_input)
      expect(result["drawings"][0]["winners"]).to eq([])
    end

    it "handles invalid timestamp format" do
      invalid_input = input.merge("timestamp" => "not-a-timestamp")

      expect { described_class.draw(invalid_input) }.to raise_error(
        MiniRacer::RuntimeError,
        /Invalid timestamp/,
      )
    end
  end
end
