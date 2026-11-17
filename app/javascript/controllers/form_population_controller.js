import { Controller } from "@hotwired/stimulus"

// Choosing who's on a printable list or tally: changing a choice's own
// setting selects that choice. Picking people by a question takes two steps,
// a form and then one of its questions, and only the chosen question's
// answers show.
export default class extends Controller {
  static targets = [ "form", "question", "answers" ]

  choose(event) {
    const radio = this.element.querySelector(`input[type=radio][name=who][value="${event.target.dataset.who}"]`)
    if (radio) radio.checked = true
  }

  // One question list per form; only the chosen form's is shown and sent.
  showQuestions() {
    const form = this.formTarget.value
    this.questionTargets.forEach((element) => {
      const shown = element.dataset.form === form
      element.hidden = !shown
      element.disabled = !shown
      if (!shown) element.value = ""
    })
    this.showAnswers()
  }

  showAnswers() {
    const question = this.questionTargets.find((element) => !element.disabled)
    const chosen = question ? question.value : ""
    this.answersTargets.forEach((element) => { element.hidden = element.dataset.question !== chosen })
  }
}
