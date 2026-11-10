import { Controller } from "@hotwired/stimulus"

// Shows the options that apply to the selected field type, and keeps the
// "who can see / edit" descriptions in step with the selected levels.
export default class extends Controller {
  static targets = [ "dataType", "option", "readLevel", "writeLevel", "readDescription", "writeDescription" ]
  static values = { descriptions: Object }

  connect() {
    this.update()
  }

  update() {
    if (this.hasDataTypeTarget) {
      const type = this.dataTypeTarget.value
      this.optionTargets.forEach((option) => {
        option.hidden = !option.dataset.types.split(" ").includes(type)
      })
    }
    if (this.hasReadLevelTarget && this.hasReadDescriptionTarget) {
      this.readDescriptionTarget.textContent = this.descriptionsValue[this.readLevelTarget.value] || ""
    }
    if (this.hasWriteLevelTarget && this.hasWriteDescriptionTarget) {
      this.writeDescriptionTarget.textContent = this.descriptionsValue[this.writeLevelTarget.value] || ""
    }
  }
}
