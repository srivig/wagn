
shared_examples_for 'machine input' do 
  subject(:input) do
    myinput = create_machine_input_card
    myinput
  end
  let!(:machine) do
    f = create_machine_card 
    f << create_machine_input_card
    f.putty
    f
  end
  
  context 'when removed' do
    it 'updates machine_input card of machine card' do
      machine
      Card::Auth.as_bot do
        input.delete!
      end
      f = Card.gimme machine.name
      expect(f.machine_input_card.item_cards).to eq([])
    end
    
    it 'updates file of machine card' do
      machine
      Card::Auth.as_bot do
        input.delete!
      end
      f = Card.gimme machine.cardname
      path = f.machine_output_path
      expect(File.read path).to eq('')
    end
  end
  
  it 'delivers machine input' do
    expect(input.machine_input).to eq(card_content[:out])
  end
  
  context 'when updated' do
    it 'updates file of related factory card' do
      input.putty :content => card_content[:new_in]
      updated_machine  = Card.gimme machine.cardname
      path = updated_machine.machine_output_path
      expect(File.read path).to eq(card_content[:new_out])
    end
  end
end

