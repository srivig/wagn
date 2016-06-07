# -*- encoding : utf-8 -*-

describe Card::Format do

  describe '#show?' do
    let(:format) { described_class.new Card.new }

    it "should respect defaults" do
      expect(format.show_view?( :menu, :default_visibility=>:show )).to be_truthy
      expect(format.show_view?( :menu, :default_visibility=>:hide )).to be_falsey
      expect(format.show_view?( :menu, {}                          )).to be_truthy
    end
    
    it "should respect developer default overrides" do
      expect(format.show_view?( :menu, :optional_menu=>:show, :default_visibility=>:hide )).to be_truthy
      expect(format.show_view?( :menu, :optional_menu=>:hide, :default_visibility=>:show )).to be_falsey
      expect(format.show_view?( :menu, :optional_menu=>:hide                             )).to be_falsey
    end
    
    it "should handle args from inclusions" do
      expect(format.show_view?( :menu, :show=>'menu', :default_visibility=>:hide         )).to be_truthy
      expect(format.show_view?( :menu, :hide=>'menu, paging', :default_visibility=>:show )).to be_falsey
      expect(format.show_view?( :menu, :show=>'menu', :optional_menu=>:hide              )).to be_truthy      
    end
    
    it "should handle hard developer overrides" do
      expect(format.show_view?( :menu, :optional_menu=>:always, :hide=>'menu' )).to be_truthy
      expect(format.show_view?( :menu, :optional_menu=>:never,  :show=>'menu' )).to be_falsey
    end
    
  end

  describe 'format helpers and link building' do
    before :each do
      # should be a way to get these defaults in these tests
      Card::Env[:host] = '//test.host'
      Card::Env[:protocol] = 'http:'
    end

    let(:card) { Card['Home'] }
    let(:text_format) { card.format(:text)}
    let(:html_format) { card.format }
    let(:url_text1) { 'with external free link http://localhost:2020/path?cgi=foo&bar=baz' }
    let(:url_text2) { 'with external in link syntax: [[http://brain.org/Home|extra]]' }
    let(:url_text3) { 'with internal lik [[A]]' }
    let(:url_text4) { 'with internal lik [[Home|display text]]' }
    let(:url_text5) { 'external with port: http://localhost:2020/path?cgi=foo+bar=baz after '}

    it "should format links" do
      cobj = Card::Content.new url_text1, text_format
      expect(cobj.to_s).to eq url_text1
      cobj = Card::Content.new url_text2, text_format
      expect(cobj.to_s).to eq url_text2
      cobj = Card::Content.new url_text3, text_format
      expect(cobj.to_s).to eq url_text3
      cobj = Card::Content.new url_text4, text_format
      expect(cobj.to_s).to eq url_text4
      cobj = Card::Content.new url_text5, text_format
      expect(cobj.to_s).to eq url_text5
    end

    it "should format html links" do
      cobj = Card::Content.new url_text1, html_format
      expect(cobj.to_s).to eq "with external free link <a class=\"external-link\" href=\"http://localhost:2020/path?cgi=foo&amp;bar=baz\">http://localhost:2020/path?cgi=foo&bar=baz</a>"
      cobj = Card::Content.new url_text2+url_text3+url_text4, html_format
      expect(cobj.to_s).to eq url_text2+url_text3+url_text4
      cobj = Card::Content.new url_text5, html_format
      expect(cobj.to_s).to eq "external with port: <a class=\"external-link\" href=\"http://localhost:2020/path?cgi=foo+bar=baz\">http://localhost:2020/path?cgi=foo+bar=baz</a> after "
    end

    it "formats page_path" do
      expect(text_format.page_path card.cardname).to eq '/'+card.name
      expect(html_format.page_path card.cardname).to eq '/'+card.name
      expect(text_format.page_path card.cardname, :format => 'txt', :opt1 => 11, :opt2 => 'foo').to eq "/#{card.name}.txt?opt1=11&opt2=foo"
    end

    it "fomats full path and url" do
      expect(text_format.card_path card.name).to eq "/#{card.name}"
      expect(html_format.card_url card.name).to eq "http://test.host/#{card.name}"
    end
  end
end
