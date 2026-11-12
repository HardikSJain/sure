import { Controller } from "@hotwired/stimulus";

// Hover (or touch) the room forecast's chart: a guide line and dot follow the
// nearest day, and a card shows that day's balance and what happens on it.
// Day positions come precomputed in viewBox units from the server.
export default class extends Controller {
  static targets = ["svg", "guide", "dot", "tooltip", "date", "balance", "events"];
  static values = { days: Array };

  move(event) {
    if (!this.daysValue.length) return;

    const rect = this.svgTarget.getBoundingClientRect();
    const viewBox = this.svgTarget.viewBox.baseVal;
    const x = ((event.clientX - rect.left) / rect.width) * viewBox.width;
    const day = this.daysValue.reduce((best, d) => (Math.abs(d.x - x) < Math.abs(best.x - x) ? d : best));

    this.guideTarget.setAttribute("x1", day.x);
    this.guideTarget.setAttribute("x2", day.x);
    this.dotTarget.setAttribute("cx", day.x);
    this.dotTarget.setAttribute("cy", day.y);
    this.guideTarget.classList.remove("hidden");
    this.dotTarget.classList.remove("hidden");

    this.dateTarget.textContent = day.date;
    this.balanceTarget.textContent = day.balance;
    this.balanceTarget.classList.toggle("text-destructive", day.under);
    this.eventsTarget.replaceChildren(
      ...day.events.map((text) => {
        const li = document.createElement("li");
        li.textContent = text;
        return li;
      }),
    );

    const left = (day.x / viewBox.width) * rect.width;
    const half = this.tooltipTarget.offsetWidth / 2 || 112;
    this.tooltipTarget.style.left = `${Math.min(Math.max(left, half), rect.width - half)}px`;
    this.tooltipTarget.style.top = `${(day.y / viewBox.height) * rect.height + 14}px`;
    this.tooltipTarget.classList.remove("hidden");
  }

  hide() {
    this.guideTarget.classList.add("hidden");
    this.dotTarget.classList.add("hidden");
    this.tooltipTarget.classList.add("hidden");
  }
}
