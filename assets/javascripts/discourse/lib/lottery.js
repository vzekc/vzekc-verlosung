import { SeededRandom } from "./prng";

export class Lottery {
  constructor(input) {
    this.title = input.title;
    this.timestamp = input.timestamp;
    this.drawings = [];
    this.rnd = null; // Initialize RNG to null
    this.initialized = false;
    this.input = input; // Store the input data

    // Convert packets to internal format
    for (const packet of input.packets) {
      const names = [];
      for (const participant of packet.participants) {
        names.push(...Array(participant.tickets).fill(participant.name));
      }

      this.drawings.push({
        text: packet.title,
        names,
        quantity: packet.quantity || 1,
      });
    }
  }

  async initialize() {
    // Parse ISO timestamp and convert to UTC
    const dt = new Date(this.timestamp);
    if (isNaN(dt.getTime())) {
      throw new Error(
        "Invalid timestamp format. Use ISO-8601 with timezone offset"
      );
    }
    const timestampStr = Math.floor(dt.getTime() / 1000).toString();

    // Create hash using Web Crypto API (SHA-512)
    const encoder = new TextEncoder();
    let hashData = encoder.encode(timestampStr);

    // Include all participant names in the hash value
    // First collect all names from all drawings
    const allNames = new Set();
    for (const drawing of this.drawings) {
      // Sort names within each drawing first
      const sortedNames = [...drawing.names].sort();
      for (const name of sortedNames) {
        allNames.add(name);
        // Update hash with each name as we go
        const nameData = encoder.encode(name);
        const combined = new Uint8Array(hashData.length + nameData.length);
        combined.set(hashData);
        combined.set(nameData, hashData.length);
        hashData = combined;
      }
    }

    // Calculate SHA-512 hash
    const hashBuffer = await crypto.subtle.digest("SHA-512", hashData);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    this.seed = hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");

    // Create a single RNG instance
    this.rnd = new SeededRandom(this.seed);
    this.initialized = true;
    return this;
  }

  _drawWinners(text, names, quantity = 1) {
    if (!this.initialized || !this.rnd) {
      throw new Error("Random number generator not initialized");
    }

    // Handle case where no tickets were claimed
    if (names.length === 0) {
      return {
        text,
        quantity,
        participants: [],
        winners: [],
      };
    }

    // Sort names for deterministic behavior
    names.sort();

    // Count tickets per participant
    const counts = {};
    for (const name of names) {
      counts[name] = (counts[name] || 0) + 1;
    }

    // Get unique participants
    const uniqueParticipants = [...new Set(names)];

    // Determine how many winners we can draw (min of quantity and unique participants)
    const maxWinners = Math.min(quantity, uniqueParticipants.length);

    // Draw winners one by one, removing each winner from the pool
    const winners = [];
    let remainingPool = [...names];

    for (let i = 0; i < maxWinners; i++) {
      if (remainingPool.length === 0) {
        break;
      }

      // Draw a winner from the remaining pool
      const winner = this.rnd.choice(remainingPool);
      winners.push(winner);

      // Remove ALL entries for this winner (they can only win once per packet)
      remainingPool = remainingPool.filter((name) => name !== winner);
    }

    return {
      text,
      quantity,
      participants: Object.entries(counts).map(([name, tickets]) => ({
        name,
        tickets,
      })),
      winners,
    };
  }

  async draw() {
    if (!this.initialized || !this.rnd) {
      throw new Error("Random number generator not initialized");
    }

    const drawingTimestamp = new Date().toISOString();
    const drawings = [];

    for (const drawing of this.drawings) {
      drawings.push(
        this._drawWinners(drawing.text, drawing.names, drawing.quantity)
      );
    }

    return {
      title: this.title,
      timestamp: this.timestamp,
      drawingTimestamp,
      rngSeed: this.seed,
      packets: this.input.packets, // Use stored input data
      drawings,
    };
  }
}
