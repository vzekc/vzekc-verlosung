# frozen_string_literal: true

require "mini_racer"
require "digest"

module VzekcVerlosung
  # Runs the lottery drawing algorithm using JavaScript via MiniRacer
  # This allows server-side verification using the exact same code that runs in the browser
  class JavascriptLotteryDrawer
    TIMEOUT = 5000 # 5 seconds
    MAX_MEMORY = 10_000_000 # 10MB

    class << self
      # Draws lottery winners using the JavaScript lottery algorithm
      #
      # @param input [Hash] Drawing data with title, timestamp, packets
      # @return [Hash] Results with drawings, seed, timestamps
      # @raise [MiniRacer::Error] if JavaScript execution fails
      def draw(input)
        context = create_context
        load_lottery_code(context)
        setup_crypto_polyfill(context)

        # Pass input data as JSON string, not attached function
        input_json = input.to_json

        # Execute drawing
        result_json = context.eval(<<~JS)
          const input = #{input_json};
          const lottery = new Lottery(input);
          lottery.initializeSync();
          const result = lottery.drawSync();
          JSON.stringify(result);
        JS

        JSON.parse(result_json)
      ensure
        context&.dispose
      end

      private

      def create_context
        MiniRacer::Context.new(timeout: TIMEOUT, max_memory: MAX_MEMORY)
      end

      def load_lottery_code(context)
        # Load PRNG code
        prng_code = File.read(prng_path)
        # Load lottery code
        lottery_code = File.read(lottery_path)

        # Convert ES6 modules to plain JavaScript
        # Remove export statements and convert to global classes
        prng_code = prng_code.gsub(/export class /, "class ")
        lottery_code =
          lottery_code.gsub(/import \{[^}]+\} from ['"][^'"]+['"];?\n/, "").gsub(
            /export class /,
            "class ",
          )

        # Load into context
        context.eval(prng_code)
        context.eval(lottery_code)

        # Add synchronous versions of async methods
        context.eval(<<~JS)
          // Override Lottery to add synchronous methods for server-side use
          Lottery.prototype.initializeSync = function() {
            const dt = new Date(this.timestamp);
            if (isNaN(dt.getTime())) {
              throw new Error('Invalid timestamp format. Use ISO-8601 with timezone offset');
            }
            const timestampStr = Math.floor(dt.getTime() / 1000).toString();

            // Collect all data for hashing
            let dataToHash = timestampStr;

            const allNames = new Set();
            for (const drawing of this.drawings) {
              const sortedNames = [...drawing.names].sort();
              for (const name of sortedNames) {
                allNames.add(name);
                dataToHash += name;
              }
            }

            // Use Ruby's crypto implementation via attached function
            const hashHex = rubyDigestSHA512(dataToHash);
            this.seed = hashHex;

            this.rnd = new SeededRandom(this.seed);
            this.initialized = true;
            return this;
          };

          Lottery.prototype.drawSync = function() {
            if (!this.initialized || !this.rnd) {
              throw new Error('Random number generator not initialized');
            }

            const drawingTimestamp = new Date().toISOString();
            const drawings = [];

            for (const drawing of this.drawings) {
              drawings.push(this._drawWinner(drawing.text, drawing.names));
            }

            return {
              title: this.title,
              timestamp: this.timestamp,
              drawingTimestamp: drawingTimestamp,
              rngSeed: this.seed,
              packets: this.input.packets,
              drawings: drawings
            };
          };
        JS
      end

      def setup_crypto_polyfill(context)
        # Attach Ruby function to compute SHA-512 hash
        context.attach("rubyDigestSHA512", ->(data) { Digest::SHA512.hexdigest(data) })
      end

      def prng_path
        File.join(plugin_root, "assets", "javascripts", "discourse", "lib", "prng.js")
      end

      def lottery_path
        File.join(plugin_root, "assets", "javascripts", "discourse", "lib", "lottery.js")
      end

      def plugin_root
        File.expand_path("../..", __dir__)
      end
    end
  end
end
