import { Controller } from "@hotwired/stimulus";

// The projection's assumptions form. Keeps each slider's label in step while
// it's dragged (the page re-renders when it's released), and sends only what
// changed: a slider snaps to its step, so sending every field would quietly
// save a rounded spending figure and stop it following the data.
export default class extends Controller {
  static targets = ["output"];
  static values = { currency: String, locale: String };

  connect() {
    this.initial = new Map(this.#fields().map((field) => [field, this.#state(field)]));
  }

  update(event) {
    const input = event.target;
    const output = this.outputTargets.find((o) => o.htmlFor.value === input.id);
    if (output) output.textContent = this.#format(input);
  }

  onlyChanged() {
    const fields = this.#fields();
    // The bucket toggles go together, with the list of buckets on screen.
    const toggles = fields.filter((f) => f.name.endsWith("[counted][]") || f.name.endsWith("[shown][]"));
    const togglesChanged = toggles.some((f) => this.initial.get(f) !== this.#state(f));

    for (const field of fields) {
      const unchanged = toggles.includes(field) ? !togglesChanged : this.initial.get(field) === this.#state(field);
      if (unchanged) field.disabled = true;
    }
  }

  #fields() {
    return [...this.element.querySelectorAll("input[name^='projection[']")];
  }

  #state(field) {
    return field.type === "checkbox" ? field.checked : field.value;
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
