class ChecklistAttestationsController < InternalController
  include ChecklistsFeature

  before_action :set_checklist

  # POST /checklists/1/attestations (item_id, person_id)
  def create
    item = @checklist.checklist_items.where(kind: "attested").find(params[:item_id])
    subject = Checklists.people_covered_by(@checklist).find(params[:person_id])
    attestation = ChecklistAttestation.new(person: subject, key: item.config["key"], statement: item.config["statement"],
      attested_by: current_user.person, attested_as: item.config["attested_by"].presence || "person")
    attestation.item = item
    authorize attestation
    attestation.save!

    redirect_back fallback_location: checklist_path(@checklist), notice: "Confirmed: #{item.config["statement"]}.", status: :see_other
  end

  # DELETE /checklists/1/attestations/1?item_id=..
  def destroy
    item = @checklist.checklist_items.where(kind: "attested").find(params[:item_id])
    attestation = ChecklistAttestation.where(key: item.config["key"], person_id: Checklists.people_covered_by(@checklist).select(:id)).find(params[:id])
    attestation.item = item
    authorize attestation
    attestation.destroy!

    redirect_back fallback_location: checklist_path(@checklist), notice: "Confirmation removed.", status: :see_other
  end
end
