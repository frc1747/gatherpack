import { Controller } from "@hotwired/stimulus"

// Drag-and-drop arranging of check-in field responses on events/arrange.
export default class extends Controller {
  static values = { fieldUpdateUrl: String, renameUrl: String, fieldId: String }

  connect() {
    this.renamePendingEncoded = null;
    this.dragstartHandler = this.dragstartHandler.bind(this);
    this.dragoverHandler = this.dragoverHandler.bind(this);
    this.dropHandler = this.dropHandler.bind(this);
    this.renameSubmitHandler = this.renameSubmitHandler.bind(this);

    const element = document.querySelectorAll(".arranging-badge");
    element.forEach( (e) => { e.addEventListener("dragstart", this.dragstartHandler) });

    this.bindDropZones();

    const addNewField = document.getElementById("addNewField");
    if (addNewField) addNewField.addEventListener("click", () => this.addNewFieldHandler());

    this.renameModal = new bootstrap.Modal(document.getElementById("renameModal"));

    document.getElementById("renameSave").addEventListener("click", this.renameSubmitHandler);
    document.getElementById("renameInput").addEventListener("keydown", (ev) => {
      if (ev.key === "Enter") this.renameSubmitHandler();
    });

    this.bindRenameButtons();
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
    const sourceContainerName = sourceContainer.dataset.arrangingContainer;
    const targetContainerName = ev.target.dataset.arrangingContainer;

    ev.target.appendChild(draggedElement);

    // Update counters
    const sourceCounter = document.querySelector(`[data-arranging-count="${sourceContainerName}"]`);
    const targetCounter = document.querySelector(`[data-arranging-count="${targetContainerName}"]`);

    if (sourceCounter) {
      sourceCounter.textContent = parseInt(sourceCounter.textContent) - 1;
    }
    if (targetCounter) {
      targetCounter.textContent = parseInt(targetCounter.textContent) + 1;
    }

    const csrfToken = document.querySelector("[name='csrf-token']").content

    fetch(this.fieldUpdateUrlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ field_id: data, response: decodeURIComponent(ev.target.dataset.arrangingContainer) })
    }).then(response => {
      if (!response.ok) { throw response; }
    }).catch(error => {
      console.error("error", error);
    })
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
    this.bindRenameButtons();
  }

  bindDropZones() {
    // addEventListener ignores a listener that is already attached, so this is safe to repeat.
    const zones = document.querySelectorAll(".arranging-container");
    zones.forEach( (e) => { e.addEventListener("drop", this.dropHandler) });
    zones.forEach( (e) => { e.addEventListener("dragover", this.dragoverHandler) });
  }

  bindRenameButtons() {
    document.querySelectorAll(".rename-btn").forEach((btn) => {
      if (btn.dataset.renameBound) return;
      btn.dataset.renameBound = "1";
      btn.addEventListener("click", () => {
        this.renamePendingEncoded = btn.dataset.arrangingLabel;
        document.getElementById("renameInput").value = btn.dataset.currentValue;
        document.getElementById("renameError").classList.add("d-none");
        this.renameModal.show();
        setTimeout(() => document.getElementById("renameInput").select(), 300);
      });
    });
  }

  renameSubmitHandler() {
    if (!this.renamePendingEncoded) return;
    const oldEncoded = this.renamePendingEncoded;
    const newVal = document.getElementById("renameInput").value.trim();
    const newEncoded = encodeURIComponent(newVal);
    const csrfToken = document.querySelector("[name='csrf-token']").content;
    const saveBtn = document.getElementById("renameSave");
    const errorEl = document.getElementById("renameError");

    saveBtn.disabled = true;

    fetch(this.renameUrlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        field_id: this.fieldIdValue || null,
        old_response: decodeURIComponent(oldEncoded),
        new_response: newVal
      })
    }).then((response) => {
      if (!response.ok) { throw new Error(`Server error ${response.status}`); }

      // Update label text & data attributes
      const label = document.querySelector(`.arranging-label[data-arranging-label="${oldEncoded}"]`);
      label.textContent = newVal || "unassigned";
      label.dataset.arrangingLabel = newEncoded;

      const counter = document.querySelector(`[data-arranging-count="${oldEncoded}"]`);
      counter.dataset.arrangingCount = newEncoded;

      const container = document.querySelector(`.arranging-container[data-arranging-container="${oldEncoded}"]`);
      container.dataset.arrangingContainer = newEncoded;

      const renameBtn = document.querySelector(`.rename-btn[data-arranging-label="${oldEncoded}"]`);
      renameBtn.dataset.arrangingLabel = newEncoded;
      renameBtn.dataset.currentValue = newVal;

      this.renamePendingEncoded = null;
      this.renameModal.hide();
    }).catch((error) => {
      errorEl.textContent = `Rename failed: ${error.message}`;
      errorEl.classList.remove("d-none");
    }).finally(() => {
      saveBtn.disabled = false;
    });
  }
}
