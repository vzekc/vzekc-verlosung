export default function () {
  this.route("lotteryHistory", { path: "/lottery-history" });
  this.route("activeLotteries", { path: "/lotteries" });
  this.route("activeDonations", { path: "/active-donations" });
  this.route("newLottery", { path: "/new-lottery" });
}
