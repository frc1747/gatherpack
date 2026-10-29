import { Controller } from "@hotwired/stimulus"

// Drag-and-drop arranging of check-in field responses on events/arrange.
export default class extends Controller {
  static values = { fieldUpdateUrl: String }

  connect() {
    this.dragstartHandler = this.dragstartHandler.bind(this);
    this.dragoverHandler = this.dragoverHandler.bind(this);
    this.dropHandler = this.dropHandler.bind(this);

    const element = document.querySelectorAll(".arranging-badge");
    element.forEach( (e) => { e.addEventListener("dragstart", this.dragstartHandler) });

    this.bindDropZones();

    const addNewField = document.getElementById("addNewField");
    if (addNewField) addNewField.addEventListener("click", () => this.addNewFieldHandler());
  }

  dragstartHandler(ev) {
    ev.dataTransfer.setData("text/plain", ev.target.id);
  }

  dragoverHandler(ev) {
    ev.preventDefault();
    ev.dataTransfer.dropEffect = "move";
  }

  dropHandler(ev) {
    ev.preventDefault();
    const data = ev.dataTransfer.getData("text/plain");
    const draggedElement = document.getElementById(data);
    const sourceContainer = draggedElement.parentElement;
    // The drop may land on a badge inside the container; the listener is on the container itself.
    const targetContainer = ev.currentTarget;
    const targetContainerName = targetContainer.dataset.arrangingContainer;

    this.moveBadge(draggedElement, sourceContainer, targetContainer);

    const csrfToken = document.querySelector("[name='csrf-token']").content

    fetch(this.fieldUpdateUrlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Content-Type": "application/json"
      },
      // The "unassigned" group has an empty key and holds nil responses.
      body: JSON.stringify({ field_id: data, response: targetContainerName === "" ? null : decodeURIComponent(targetContainerName) })
    }).then(response => {
      if (!response.ok) { throw response; }
    }).catch(error => {
      // The change wasn't saved (refused or failed), so put the badge back.
      this.moveBadge(draggedElement, targetContainer, sourceContainer);
      console.error("error", error);
    })
  }

  moveBadge(badge, from, to) {
    to.appendChild(badge);

    const fromCounter = document.querySelector(`[data-arranging-count="${from.dataset.arrangingContainer}"]`);
    const toCounter = document.querySelector(`[data-arranging-count="${to.dataset.arrangingContainer}"]`);

    if (fromCounter) {
      fromCounter.textContent = parseInt(fromCounter.textContent) - 1;
    }
    if (toCounter) {
      toCounter.textContent = parseInt(toCounter.textContent) + 1;
    }
  }

  addNewFieldHandler() {
    const val = document.getElementById("newField").value;
    const encoded = encodeURIComponent(val);
    const template = `<div class="row align-items-center">
          <div class="col-12 col-md-4 col-xl-2">
            <h3 class="d-flex align-items-center gap-2">
              <span class="arranging-label" data-arranging-label="${encoded}">${val}</span>
              [<span data-arranging-count="${encoded}">0</span>]
              <button class="btn btn-sm btn-outline-secondary rename-btn" title="Rename"
                data-arranging-label="${encoded}" data-current-value="${val}">&#9998;</button>
            </h3>
          </div>
          <div class="col-12 col-md-8 col-xl-10">
            <div class="badge-container arranging-container" data-arranging-container="${encoded}">
            </div>
          </div>
        </div>`;
    document.getElementById("responseContainer").insertAdjacentHTML("afterbegin", template);
    this.bindDropZones();
  }

  bindDropZones() {
    // addEventListener ignores a listener that is already attached, so this is safe to repeat.
    const zones = document.querySelectorAll(".arranging-container");
    zones.forEach( (e) => { e.addEventListener("drop", this.dropHandler) });
    zones.forEach( (e) => { e.addEventListener("dragover", this.dragoverHandler) });
  }
}
