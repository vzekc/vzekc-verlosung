# frozen_string_literal: true

module Jobs
  # Deletes Herold email handoffs whose one-time link was never opened.
  class VzekcVerlosungEmailHandoffCleanup < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      VzekcVerlosung::EmailHandoff.expired.find_each(&:destroy!)
    end
  end
end
