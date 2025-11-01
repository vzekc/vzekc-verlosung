# frozen_string_literal: true

RSpec.describe VzekcVerlosung::CreateLottery do
  fab!(:user)
  fab!(:category)

  let(:valid_params) do
    {
      user: user,
      guardian: Guardian.new(user),
      title: "Hardware Verlosung Januar 2025",
      description: "Eine tolle Verlosung mit vielen Preisen",
      category_id: category.id,
      packets: [
        { "title" => "Packet 1", "description" => "Inhalt 1" },
        { "title" => "Packet 2", "description" => "Inhalt 2" },
      ],
    }
  end

  describe "#call" do
    context "when user can create topics" do
      it "creates main topic and packet topics" do
        expect { described_class.call(**valid_params) }.to change { Topic.count }.by(3).and change {
                Post.count
              }.by(3)
      end

      it "returns success with main topic" do
        result = described_class.call(**valid_params)

        expect(result).to be_success
        expect(result.main_topic).to be_a(Topic)
        expect(result.main_topic.title).to eq("Hardware Verlosung Januar 2025")
      end

      it "marks the main topic as a draft" do
        result = described_class.call(**valid_params)

        expect(result.main_topic.custom_fields["lottery_state"]).to eq("draft")
      end

      it "marks the intro post with is_lottery_intro" do
        result = described_class.call(**valid_params)

        intro_post = result.main_topic.first_post
        expect(intro_post.custom_fields["is_lottery_intro"]).to eq(true)
      end

      it "creates packet topics in the same category" do
        result = described_class.call(**valid_params)

        packet_topics = Topic.where(category_id: category.id).where.not(id: result.main_topic.id)
        expect(packet_topics.count).to eq(2)
        expect(packet_topics.pluck(:title)).to contain_exactly("Packet 1", "Packet 2")
      end

      it "updates main topic with links to packet topics" do
        result = described_class.call(**valid_params)

        main_post_content = result.main_topic.first_post.raw
        expect(main_post_content).to include("## Pakete")
        expect(main_post_content).to include("[Packet 1]")
        expect(main_post_content).to include("[Packet 2]")
      end

      it "includes image in packet post when image_url provided" do
        result = described_class.call(**valid_params)

        packet_with_image = Topic.find_by(title: "Packet 2")
        expect(packet_with_image.first_post.raw).to include("![](https://example.com/image.jpg)")
      end
    end

    context "when user cannot create topics" do
      fab!(:readonly_category) { Fabricate(:private_category, group: Fabricate(:group)) }

      let(:params_with_readonly_category) do
        valid_params.merge(category_id: readonly_category.id)
      end

      it "fails with policy error" do
        result = described_class.call(**params_with_readonly_category)

        expect(result).to be_failure
      end
    end

    context "with invalid params" do
      it "fails when title is missing" do
        invalid_params = valid_params.merge(title: "")
        result = described_class.call(**invalid_params)

        expect(result).to be_failure
      end

      it "fails when packets array is empty" do
        invalid_params = valid_params.merge(packets: [])
        result = described_class.call(**invalid_params)

        expect(result).to be_failure
      end

      it "fails when category does not exist" do
        invalid_params = valid_params.merge(category_id: 99_999)
        result = described_class.call(**invalid_params)

        expect(result).to be_failure
      end
    end
  end
end
