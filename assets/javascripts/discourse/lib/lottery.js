import { SeededRandom } from "./prng.js";

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

  _drawWinner(text, names) {
    if (!this.initialized || !this.rnd) {
      throw new Error("Random number generator not initialized");
    }

    names.sort();
    const counts = {};
    for (const name of names) {
      counts[name] = (counts[name] || 0) + 1;
    }

    const winner = this.rnd.choice(names);

    return {
      text,
      participants: Object.entries(counts).map(([name, tickets]) => ({
        name,
        tickets,
      })),
      winner,
    };
  }

  async draw() {
    if (!this.initialized || !this.rnd) {
      throw new Error("Random number generator not initialized");
    }

    const drawingTimestamp = new Date().toISOString();
    const drawings = [];

    for (const drawing of this.drawings) {
      drawings.push(this._drawWinner(drawing.text, drawing.names));
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
