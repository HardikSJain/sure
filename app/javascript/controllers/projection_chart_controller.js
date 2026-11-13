import { Controller } from "@hotwired/stimulus";

// Hover (or touch) the projection chart: a guide line and dot follow the
// nearest month, and a card shows its middle estimate and the range.
// Month positions come precomputed in viewBox units from the server.
export default class extends Controller {
  static targets = ["svg", "guide", "dot", "tooltip", "month", "middle", "range"];
  static values = { months: Array };

  move(event) {
    if (!this.monthsValue.length) return;

    const rect = this.svgTarget.getBoundingClientRect();
    const viewBox = this.svgTarget.viewBox.baseVal;
    const x = ((event.clientX - rect.left) / rect.width) * viewBox.width;
    const month = this.monthsValue.reduce((best, m) => (Math.abs(m.x - x) < Math.abs(best.x - x) ? m : best));

    this.guideTarget.setAttribute("x1", month.x);
    this.guideTarget.setAttribute("x2", month.x);
    this.dotTarget.style.left = `${(month.x / viewBox.width) * 100}%`;
    this.dotTarget.style.top = `${(month.y / viewBox.height) * 100}%`;
    this.guideTarget.classList.remove("hidden");
    this.dotTarget.classList.remove("hidden");

    this.monthTarget.textContent = month.month;
    this.middleTarget.textContent = month.middle;
    this.rangeTarget.textContent = month.range;

    const left = (month.x / viewBox.width) * rect.width;
    const half = this.tooltipTarget.offsetWidth / 2 || 96;
    this.tooltipTarget.style.left = `${Math.min(Math.max(left, half), rect.width - half)}px`;
    this.tooltipTarget.style.top = `${(month.y / viewBox.height) * rect.height + 14}px`;
    this.tooltipTarget.classList.remove("hidden");
  }

  hide() {
    this.guideTarget.classList.add("hidden");
    this.dotTarget.classList.add("hidden");
    this.tooltipTarget.classList.add("hidden");
  }
}
