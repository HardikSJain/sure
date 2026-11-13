import { Controller } from "@hotwired/stimulus";

// Keeps each slider's label in step while it's dragged. The page itself
// re-renders when the slider is released (auto-submit-form on change).
export default class extends Controller {
  static targets = ["output"];
  static values = { currency: String, locale: String };

  update(event) {
    const input = event.target;
    const output = this.outputTargets.find((o) => o.htmlFor.value === input.id);
    if (output) output.textContent = this.#format(input);
  }

  #format(input) {
    const value = Number(input.value);
    switch (input.dataset.format) {
      case "percent":
        return `${value}%`;
      case "money":
        return new Intl.NumberFormat(this.localeValue || undefined, {
          style: "currency",
          currency: this.currencyValue,
          maximumFractionDigits: 0,
        }).format(value);
      default:
        return String(value);
    }
  }
}
