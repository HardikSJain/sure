import { computePosition, flip, offset, shift } from "@floating-ui/dom";
import { Controller } from "@hotwired/stimulus";

// Hover card for the dashboard's spending calendar: one card, filled from the
// hovered (or keyboard-focused) day's data attributes and placed above it.
export default class extends Controller {
  static targets = ["tooltip", "date", "total", "items", "empty"];

  show(event) {
    const cell = event.currentTarget;
    const items = JSON.parse(cell.dataset.items || "[]");

    this.dateTarget.textContent = cell.dataset.date;
    this.totalTarget.textContent = cell.dataset.total;
    this.itemsTarget.replaceChildren(
      ...items.map(([name, amount]) => {
        const li = document.createElement("li");
        li.className = "flex items-baseline justify-between gap-2";
        const label = document.createElement("span");
        label.className = "truncate";
        label.textContent = name;
        const value = document.createElement("span");
        value.className = "whitespace-nowrap privacy-sensitive";
        value.textContent = amount;
        li.append(label, value);
        return li;
      }),
    );
    this.emptyTarget.classList.toggle("hidden", items.length > 0);
    this.tooltipTarget.classList.remove("hidden");

    computePosition(cell, this.tooltipTarget, {
      placement: "top",
      strategy: "absolute",
      middleware: [offset(8), flip(), shift({ padding: 8 })],
    }).then(({ x, y }) => {
      Object.assign(this.tooltipTarget.style, { left: `${x}px`, top: `${y}px` });
    });
  }

  hide() {
    this.tooltipTarget.classList.add("hidden");
  }
}
