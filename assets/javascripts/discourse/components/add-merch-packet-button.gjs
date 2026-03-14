import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import CreateMerchPacketModal from "./modal/create-merch-packet-modal";

/**
 * Button to open the create merch packet modal
 *
 * @component AddMerchPacketButton
 * @param {Function} onCreated - Callback when a packet is created
 */
export default class AddMerchPacketButton extends Component {
  @service modal;

  @action
  openCreateModal() {
    this.modal.show(CreateMerchPacketModal, {
      model: {
        onCreated: this.args.onCreated,
      },
    });
  }

  <template>
    <DButton
      @action={{this.openCreateModal}}
      @icon="plus"
      @label="vzekc_verlosung.merch_packets.add"
      class="btn-primary"
    />
  </template>
}
