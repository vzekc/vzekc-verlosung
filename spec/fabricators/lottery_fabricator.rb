# frozen_string_literal: true

# Local counter to avoid global sequence overflow
# Thread-safe incrementing counter starting at 401
module LotteryDisplayIdCounter
  @counter = 401
  @mutex = Mutex.new

  def self.next_id
    @mutex.synchronize { @counter += 1 }
  end
end

Fabricator(:lottery, from: "VzekcVerlosung::Lottery") do
  topic { Fabricate(:topic) }
  # Use local counter instead of global sequence to avoid overflow
  # Maintains realistic Woltlab forum donation numbers (401+)
  display_id { LotteryDisplayIdCounter.next_id }
  state "draft"
  duration_days 14
end
