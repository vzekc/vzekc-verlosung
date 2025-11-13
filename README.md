# Vzekc Verlosung Plugin

A Discourse plugin for creating and managing lotteries with ticket-based participation and deterministic, verifiable drawing.

## Features

- **Lottery Creation**: Single-step modal for creating lotteries with multiple packets
- **Ticket System**: Users can buy tickets for individual packets
- **Draft Mode**: Create lotteries as drafts before publishing
- **Time-Based State Management**: Automatic state transitions (draft → active → finished)
- **Deterministic Drawing**: Browser-based drawing using seeded PRNG for verifiable results
- **Guardian Integration**: Permission checks for creating, publishing, and drawing lotteries

## Lottery Lifecycle

1. **Draft**: Lottery is created but not visible to other users
2. **Active**: Lottery is published and accepting tickets (runs for 2 weeks)
3. **Finished**: Lottery has ended, ready for drawing or already drawn

## Development

### Running Tests

```bash
# Ruby specs
LOAD_PLUGINS=1 bin/rspec plugins/vzekc-verlosung/spec

# Specific test file
LOAD_PLUGINS=1 bin/rspec plugins/vzekc-verlosung/spec/requests/vzekc_verlosung/lotteries_controller_spec.rb
```

### Linting

**Important**: Linting commands must be run from the Discourse root directory.

```bash
cd /Users/hans/Development/vzekc/discourse

# Lint all plugin files
bin/lint --fix plugins/vzekc-verlosung/

# Lint specific files
bin/lint --fix \
  plugins/vzekc-verlosung/plugin.rb \
  plugins/vzekc-verlosung/app/controllers/vzekc_verlosung/lotteries_controller.rb
```

## Demo Data Scripts

### Creating Demo Lotteries

**All-in-One Setup** (recommended) - Creates, populates, and publishes 4 lotteries:
```bash
# Random owners from vereinsmitglied group
LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/setup_full_demo.rb

# Or specify owner for all lotteries
LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/setup_full_demo.rb hans
```

This creates four complete lotteries:
1. **Business Liquidation** - TechnoData GmbH CAD workstations (8 packets)
2. **Private Collector** - Werner K. home computer collection (10 packets)
3. **Estate/Inheritance** - Dr. Schmidt IBM PC history (11 packets)
4. **School Donation** - Heinrich-Hertz-Gymnasium educational hardware (12 packets)

Each includes:
- Realistic German descriptions with donation source backstory
- "Behaltene Systeme" section (what donor kept)
- Pickup and shipping arrangements
- Random participants with tickets
- One packet per lottery with NO tickets (for testing)
- Published and active state

**Just Create (without participants)**:
```bash
# Random owners from vereinsmitglied group
LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/create_demo_lotteries.rb

# Or specify owner
LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/create_demo_lotteries.rb hans
```

**Single Test Lottery**:
```bash
LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/create_test_lottery.rb <username>
```

### Lottery Management Utility

The `test_lottery.rb` script provides various commands:

```bash
# Create test lottery
LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/test_lottery.rb create <username>

# Add participants
LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/test_lottery.rb add_participants <topic_id>

# Publish lottery
LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/test_lottery.rb publish <topic_id>

# End lottery early (for testing)
LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/test_lottery.rb end_early <topic_id>

# List all lotteries
LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/test_lottery.rb list
```

## Testing the Drawing Feature

The drawing feature requires a lottery to have ended. To test this in development:

### 1. Create and Publish a Lottery

**Option A: Use all-in-one script** (recommended):
```bash
# Create 4 complete lotteries (with participants, published)
LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/setup_full_demo.rb
```

This creates everything you need in one step. Each lottery has random participants and is already published.

**Option B: Manual via UI**:
1. Navigate to the lottery category
2. Click "Neue Verlosung" (New Lottery) button
3. Fill in lottery details and add packets
4. Click "Create Lottery" to create as draft
5. Click "Publish Lottery" to activate it

### 2. Force Lottery to End

Use the Rails console to set the end time to the past:

```bash
# Start Rails console
bundle exec rails c

# Find your lottery topic
topic = Topic.find(YOUR_TOPIC_ID)
# Or by title:
# topic = Topic.find_by(title: "Your Lottery Title")

# Set lottery to end now
topic.custom_fields["lottery_ends_at"] = Time.zone.now - 1.minute
topic.save_custom_fields

# Verify it's ready to draw
puts "State: #{topic.lottery_state}"
puts "Ends at: #{topic.lottery_ends_at}"
puts "Has ended: #{topic.lottery_ends_at <= Time.zone.now}"
puts "Already drawn: #{topic.lottery_drawn?}"
```

**Quick one-liner**:
```ruby
topic = Topic.find(123); topic.custom_fields["lottery_ends_at"] = Time.zone.now - 1.minute; topic.save_custom_fields; "Ready to draw!"
```

### 3. Draw Winners

1. Refresh the lottery topic page
2. You should see a "Draw Winners" button (only visible to lottery creator/staff)
3. Click the button to open the drawing modal
4. Click "Draw Winners" to perform the deterministic drawing
5. Review the results and click "Confirm and Save Results"

### 4. Verify Results

The drawing results are stored in:
- `topic.custom_fields["lottery_results"]` - Full drawing data (JSON)
- `topic.custom_fields["lottery_drawn_at"]` - Timestamp of drawing
- `post.custom_fields["lottery_winner"]` - Winner username on each packet post

```ruby
# In Rails console
topic = Topic.find(YOUR_TOPIC_ID)
puts JSON.pretty_generate(topic.lottery_results)
```

## Architecture

### Custom Fields

**Topic Custom Fields**:
- `lottery_state` (string): "draft", "active", or "finished"
- `lottery_ends_at` (datetime): When the lottery ends (set to 2 weeks after publishing)
- `lottery_results` (JSON): Full drawing results from lottery.js
- `lottery_drawn_at` (datetime): When the drawing was performed

**Post Serializer Fields** (computed, not stored as custom fields):
- `is_lottery_intro` (boolean): True if post_number == 1 in a lottery topic
- `is_lottery_packet` (boolean): True if post has a LotteryPacket record
- `is_abholerpaket` (boolean): True if the packet is marked as Abholerpaket
- `lottery_winner` (string): Username of the packet winner (from LotteryPacket table)

### Drawing Algorithm

The drawing uses a deterministic PRNG (xorshift64*) seeded with:
- Lottery start time (ISO 8601 timestamp)
- All participant usernames
- SHA-512 hash for seed generation

This ensures:
- Same seed always produces same results (verifiable)
- Results depend on who participated (tamper-proof)
- Drawing happens client-side (transparent)

### Key Components

**Backend**:
- `VzekcVerlosung::LotteriesController` - API endpoints
- `VzekcVerlosung::CreateLottery` - Service for lottery creation
- `VzekcVerlosung::GuardianExtensions` - Permission checks

**Frontend**:
- `CreateLotteryModal` - Single-step lottery creation modal
- `DrawLotteryModal` - Drawing interface
- `LotteryIntroSummary` - Status display and actions
- `LotteryWidget` - Ticket buying interface
- `lottery.js` - Deterministic drawing library
- `prng.js` - Seeded random number generator
