parser grammar hlasmparser;

@header
{
	#include "../parser_impl.h"
	#include "../semantics/expression.h"
	#include "../semantics/arithmetic_expression.h"
	#include "../semantics/logic_expression.h"
	#include "../semantics/character_expression.h"
	#include "../semantics/keyword_expression.h"

	namespace hlasm_plugin::parser_library::generated
	{
		using namespace hlasm_plugin::parser_library;
		using namespace hlasm_plugin::parser_library::semantics;
		using namespace hlasm_plugin::parser_library::context;
		using namespace hlasm_plugin::parser_library::checking;
	}

	/* disables unreferenced parameter (_localctx) warning */
	#ifdef _MSC_VER
		#pragma warning(push)
		#pragma warning(disable: 4100)
	#endif
}

@footer 
{
	#ifdef _MSC_VER
		#pragma warning(pop)
	#endif
}

options {
    tokenVocab = lex;
	superClass = parser_impl;
}

@members 
{
	#define last_text() _input->LT(-1)->getText()
	#define text(token) token->getText()
}

program :  prcs*  program_block  EOF;

/*
program :  ictl? prcs*  program_block  EOF;

ictl: { _input->LT(2)->getText() == "ICTL" }? SPACE ORDSYMBOL SPACE ictl_begin EOLLN{ analyzer.get_lexer()->set_ictl(); };

ictl_begin: IDENTIFIER ictl_end? 
				{ 
					size_t idx = 0;
					auto val = std::stoi($IDENTIFIER.text, &idx);
					if(idx > 0 || !analyzer.get_lexer()->set_begin(val))
						throw RecognitionException("invalid ICTL parameter value", this, _input, _localctx, $IDENTIFIER); 
					semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($IDENTIFIER),scopes::operand));
				}
			;

ictl_end: COMMA IDENTIFIER ictl_continue 
				{ 
					size_t idx = 0;
					auto val = std::stoi($IDENTIFIER.text, &idx);
					if(idx > 0 || !analyzer.get_lexer()->set_end(val))
						throw RecognitionException("invalid ICTL parameter value", this, _input, _localctx, $IDENTIFIER); 
					semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($COMMA),scopes::operator_symbol));
					semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($IDENTIFIER),scopes::operand));
				}
			;

ictl_continue:  { analyzer.get_lexer()->set_continuation_enabled(false); }

                | COMMA IDENTIFIER 
					{ 
						size_t idx = 0;
						auto val = std::stoi($IDENTIFIER.text, &idx);
						if(idx > 0 || !analyzer.get_lexer()->set_continue(val))
							throw RecognitionException("invalid ICTL parameter value", this, _input, _ctx, $IDENTIFIER);
							
						semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($COMMA),scopes::operator_symbol));
						semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($IDENTIFIER),scopes::operand));
					}
				;
*/

prcs: PROCESS SPACE (assembler_options
									| (ORDSYMBOL { $ORDSYMBOL.text == "OVERRIDE" }? LPAR assembler_options RPAR)) EOLLN;


assembler_options: assembler_option (COMMA assembler_option)*;

assembler_option: id (LPAR (list | codepage | machine | id)? RPAR)?;

list: list_item (COMMA list_item)*;

list_item: id (LPAR (id | string)+? RPAR)?;

machine: id (MINUS id)? (COMMA id)?;

codepage: id VERTICAL id string;








program_block: (instruction_statement EOLLN)*;

instruction_statement
	: { format.in_lookahead}? lookahead_instruction_statement										
	{
		collector.set_statement_range(symbol_range::get_range($lookahead_instruction_statement.ctx));
		process_statement();
	}
	| {!format.in_lookahead}? ordinary_instruction_statement										
	{
		collector.set_statement_range(symbol_range::get_range($ordinary_instruction_statement.ctx));
		process_statement();
	}
	| SPACE*					
	{
		collector.set_instruction_field(symbol_range::get_range(_localctx));
		process_instruction();
		collector.set_statement_range(symbol_range::get_range(_localctx));
		process_statement();
	};


ordinary_instruction_statement: label SPACE instruction operands_and_remarks
{
	semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($instruction.ctx),scopes::instruction));
	for (auto && operand : collector.current_operands_and_remarks().operands)
	{
		if(operand)
			semantic_info.hl_info.lines.push_back(token_info(operand->range.begin_ln, operand->range.begin_col, operand->range.end_ln, operand->range.end_col, scopes::operand));
	}
	for (auto remark : collector.current_operands_and_remarks().remarks)
	{
		semantic_info.hl_info.lines.push_back(token_info(remark.begin_ln, remark.begin_col, remark.end_ln, remark.end_col, scopes::remark));
	}
};


//lookahead rules*************************************************************************************************************************************

lookahead_instruction_statement
	: look_statement												{collector.set_statement_range(symbol_range::get_range($look_statement.ctx));}									//nothing interesting
	| look_label_o SPACE ORDSYMBOL SPACE*							
	{
		collector.set_instruction_field($ORDSYMBOL->getText(),symbol_range::get_range($ORDSYMBOL));
		process_instruction();
	}					//macro mend
	| look_label_o SPACE ORDSYMBOL SPACE+ word (SPACE ~EOLLN*)?																														//copy, macro mend
	{
		collector.set_instruction_field($ORDSYMBOL->getText(),symbol_range::get_range($ORDSYMBOL));
		process_instruction();
		//collector.set_operand_remark_field($word.ctx->getText(), symbol_range::get_range($word.ctx)); TODO make special operand
	}
	| seq_symbol ~EOLLN*											{collector.set_label_field(std::move($seq_symbol.ss),symbol_range::get_range($seq_symbol.ctx));};			//seq

look_statement
	: look_label SPACE*
	| look_label_o SPACE look_instr (SPACE (~EOLLN)*)?;

look_label
	: ~(SPACE|EOLLN) ~(SPACE|EOLLN) ~(SPACE|EOLLN)+
	| DOT ~(ORDSYMBOL|SPACE|EOLLN)
	| ~(DOT|EOLLN|SPACE) ~(SPACE|EOLLN)
	| ~(SPACE|EOLLN);

look_label_o
	: look_label
	|;

look_instr
	:  ~(SPACE|EOLLN) (~(SPACE|EOLLN))+
	| ~(ORDSYMBOL|SPACE|EOLLN);

word: (~(SPACE|EOLLN))+;

//lookahead rules*************************************************************************************************************************************



//label rules************************************************************

label
	: l_char_string															{
																				collector.set_label_field(std::move($l_char_string.value),$l_char_string.ctx); 
																				if (collector.current_label().type == label_type::SEQ)
																				{
																					semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($l_char_string.ctx),scopes::seq_symbol));
																					auto current_seq_occurence = create_occurence(symbol_range::get_range($l_char_string.ctx), collector.current_label().sequence_symbol.name);
																					semantic_info.seq_symbols.push_back(current_seq_occurence,is_seq_definition(current_seq_occurence));
																				}
																				else
																				{
																					semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($l_char_string.ctx),scopes::label));
																				}
																			}		
	| l_char_string_sp l_char_string_o										{ semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($l_char_string_sp.ctx),scopes::label)); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($l_char_string_o.ctx),scopes::label)); }
	{
		$l_char_string_sp.value.append(std::move($l_char_string_o.value));
		auto r = symbol_range::get_range($l_char_string_sp.ctx->getStart(),$l_char_string_o.ctx->getStop());
		collector.set_label_field(std::move($l_char_string_sp.value),r);
	}																				
	| l_model												
	{
		collector.set_label_field(std::move($l_model.chain),symbol_range::get_range($l_model.ctx));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($l_model.ctx),scopes::label));
	}	//model stmt rule with no space
    | l_model_sp											
	{
		collector.set_label_field(std::move($l_model_sp.chain),symbol_range::get_range($l_model_sp.ctx));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($l_model_sp.ctx),scopes::label));
	}	//model stmt rule with possible space
	|														{collector.set_label_field(symbol_range::get_empty_range(_localctx->getStart()));};

//label rules************************************************************

//label subrules*********************************************************

l_common_rules returns [concat_chain chain]
	: l_string_v_apo_sp l_string_v
	{
		$chain = std::move($l_string_v_apo_sp.chain);
		$chain.insert($chain.end(), std::make_move_iterator($l_string_v.chain.begin()), std::make_move_iterator($l_string_v.chain.end()));
	}
	| l_string_poss_space_c l_string_v
	{
		$chain.push_back(std::make_unique<char_str>(std::move($l_string_poss_space_c.value)));
		$chain.insert($chain.end(), std::make_move_iterator($l_string_v.chain.begin()), std::make_move_iterator($l_string_v.chain.end()));
	}
	| l_string_v_apo_sp l_string
	{
		$l_string_v_apo_sp.chain.push_back(std::make_unique<char_str>(std::move($l_string.value)));
		$chain = std::move($l_string_v_apo_sp.chain);
	};

l_model_sp returns [concat_chain chain]
	: l_string_v_apo_sp											{$chain = std::move($l_string_v_apo_sp.chain);}
	| l_common_rules											{$chain = std::move($l_common_rules.chain);}
	| l_common_rules l_string_v_apo
	{
		$chain = std::move($l_common_rules.chain);
		$chain.insert($chain.end(), std::make_move_iterator($l_string_v_apo.chain.begin()), std::make_move_iterator($l_string_v_apo.chain.end()));
	}
	| l_common_rules l_string_no_space_c
	{
		$chain = std::move($l_common_rules.chain);
		$chain.push_back(std::make_unique<char_str>(std::move($l_string_no_space_c.value)));
	}
	| l_string_poss_space_c l_string l_string_v_apo
	{
		$chain.push_back(std::make_unique<char_str>(std::move($l_string_poss_space_c.value)));
		$chain.push_back(std::make_unique<char_str>(std::move($l_string.value)));
		$chain.insert($chain.end(), std::make_move_iterator($l_string_v_apo.chain.begin()), std::make_move_iterator($l_string_v_apo.chain.end()));
	};

l_model returns [concat_chain chain]
	: l_string_v			
	{
		$chain = std::move($l_string_v.chain);
	}
	| l_string l_string_v_apo
	{
		$chain.push_back(std::make_unique<char_str>(std::move($l_string.value)));
		$chain.insert($chain.end(), std::make_move_iterator($l_string_v_apo.chain.begin()), std::make_move_iterator($l_string_v_apo.chain.end()));
	}
	| l_string_v l_string_v_apo
	{
		$chain = std::move($l_string_v.chain);
		$chain.insert($chain.end(), std::make_move_iterator($l_string_v_apo.chain.begin()), std::make_move_iterator($l_string_v_apo.chain.end()));
	}
	| l_string_v l_string_no_space_c
	{
		$chain = std::move($l_string_v.chain);
		$chain.push_back(std::make_unique<char_str>(std::move($l_string_no_space_c.value)));
	};



common_ch returns [std::string value]
	: ASTERISK												{$value = "*";}
	| MINUS													{$value = "-";}
	| PLUS													{$value = "+";}
	| LT													{$value = "<";}
	| GT													{$value = ">";}
	| SLASH													{$value = "/";}
	| EQUALS												{$value = "=";}
	| AMPERSAND AMPERSAND									{$value = "&&";}
	| VERTICAL												{$value = "|";}
	| IDENTIFIER											{$value = $IDENTIFIER->getText();}
	| ORDSYMBOL												{$value = $ORDSYMBOL->getText();}
	| DOT													{$value = ".";};

l_ch returns [std::string value]
	: common_ch												{$value = std::move($common_ch.value);}
	| COMMA													{$value = ",";}
	| LPAR													{$value = "(";}
	| RPAR													{$value = ")";};

common_ch_v returns [concat_point_ptr point]
	: ASTERISK												{$point = std::make_unique<char_str>("*");}
	| MINUS													{$point = std::make_unique<char_str>("-");}
	| PLUS													{$point = std::make_unique<char_str>("+");}
	| LT													{$point = std::make_unique<char_str>("<");}
	| GT													{$point = std::make_unique<char_str>(">");}
	| SLASH													{$point = std::make_unique<char_str>("/");}
	| AMPERSAND AMPERSAND									{$point = std::make_unique<char_str>("&&");}
	| VERTICAL												{$point = std::make_unique<char_str>("|");}
	| IDENTIFIER											{$point = std::make_unique<char_str>(std::move($IDENTIFIER->getText()));}
	| ORDSYMBOL												{$point = std::make_unique<char_str>(std::move($ORDSYMBOL->getText()));}
	| DOT													{$point = std::make_unique<dot>();}												
	| var_symbol											{$point = std::make_unique<var_sym>(std::move($var_symbol.vs));};

l_ch_v returns [concat_point_ptr point]
	: common_ch_v											{$point = std::move($common_ch_v.point);}
	| EQUALS												{$point = std::make_unique<char_str>("=");}
	| COMMA													{$point = std::make_unique<char_str>(",");}
	| LPAR													{$point = std::make_unique<char_str>("(");}
	| RPAR													{$point = std::make_unique<char_str>(")");};

l_str_v returns [concat_chain chain]
	:														
	| tmp=l_str_v l_ch_v									{$chain=std::move($tmp.chain);};

l_string returns [std::string value]
	: l_ch													{$value = std::move($l_ch.value);}
	| str=l_string l_ch										{$value.append(std::move($str.value)); $value.append(std::move($l_ch.value));};

l_string_v returns [concat_chain chain]
	: l_string_o var_symbol l_str_v							
	{
		$chain.push_back(std::make_unique<char_str>(std::move($l_string_o.value))); 
		$chain.push_back(std::make_unique<var_sym>(std::move($var_symbol.vs)));
		$chain.insert($chain.end(), std::make_move_iterator($l_str_v.chain.begin()), std::make_move_iterator($l_str_v.chain.end()));
	};

l_string_o returns [std::string value]
	: l_string												{$value = std::move($l_string.value);}				
	| ;

l_string_no_space_c returns [std::string value]
	: APOSTROPHE str1=l_string_o APOSTROPHE str2=l_string_o			
	{
		$value.append("'"); $value.append(std::move($str1.value)); $value.append("'"); $value.append(std::move($str2.value));
	}
	| tmp=l_string_no_space_c APOSTROPHE str1=l_string_o APOSTROPHE str2=l_string_o
	{
		$value = std::move($tmp.value); $value.append("'"); $value.append(std::move($str1.value)); $value.append("'"); $value.append(std::move($str2.value));
	};

l_string_no_space_v returns [concat_chain chain]
	: APOSTROPHE l_string_o APOSTROPHE l_string_v
	{
		std::string tmp("'"); tmp.append(std::move($l_string_o.value)); tmp.append("'");
		$chain.push_back(std::make_unique<char_str>(std::move(tmp)));
		$chain.insert($chain.end(), std::make_move_iterator($l_string_v.chain.begin()), std::make_move_iterator($l_string_v.chain.end()));
	}
	| APOSTROPHE l_string_v APOSTROPHE l_string_o
	{
		$chain.push_back(std::make_unique<char_str>("'"));
		$chain.insert($chain.end(), std::make_move_iterator($l_string_v.chain.begin()), std::make_move_iterator($l_string_v.chain.end()));
		$chain.push_back(std::make_unique<char_str>("'"));
		$chain.push_back(std::make_unique<char_str>(std::move($l_string_o.value)));
	}
	| APOSTROPHE str1=l_string_v APOSTROPHE str2=l_string_v
	{
		$chain.push_back(std::make_unique<char_str>("'"));
		$chain.insert($chain.end(), std::make_move_iterator($str1.chain.begin()), std::make_move_iterator($str1.chain.end()));
		$chain.push_back(std::make_unique<char_str>("'"));
		$chain.insert($chain.end(), std::make_move_iterator($str2.chain.begin()), std::make_move_iterator($str2.chain.end()));
	};

l_string_no_space_u returns [concat_chain chain]
	: l_string_no_space_v													{$chain = std::move($l_string_no_space_v.chain);}
	| APOSTROPHE str1=l_string_o APOSTROPHE str2=l_string_o
	{
		std::string tmp("'"); tmp.append(std::move($str1.value)); tmp.append("'");  tmp.append(std::move($str2.value));
		$chain.push_back(std::make_unique<char_str>(std::move(tmp)));
	};

l_string_no_space_u_c returns [concat_chain chain]
	:  
	| cl1=l_string_no_space_u_c cl2=l_string_no_space_u
	{
		$chain = std::move($cl1.chain);
		$chain.insert($chain.end(), std::make_move_iterator($cl2.chain.begin()), std::make_move_iterator($cl2.chain.end()));	
	};

l_string_no_space_c_o returns [std::string value]
	: l_string_no_space_c														{$value = std::move($l_string_no_space_c.value);}
	| ;

l_string_v_apo returns [concat_chain chain]
	: cl1=l_string_no_space_c_o  cl2=l_string_no_space_v cl3=l_string_no_space_u_c
	{
		$chain.push_back(std::make_unique<char_str>(std::move($cl1.value)));
		$chain.insert($chain.end(), std::make_move_iterator($cl2.chain.begin()), std::make_move_iterator($cl2.chain.end()));	
		$chain.insert($chain.end(), std::make_move_iterator($cl3.chain.begin()), std::make_move_iterator($cl3.chain.end()));
	};




l_sp_ch returns [std::string value] //l_ch with SPACE
	: l_ch															{$value = std::move($l_ch.value);}
	| SPACE															{$value = " ";}; 					
l_sp_ch_v returns [concat_point_ptr point]
	: l_sp_ch														{$point = std::make_unique<char_str>(std::move($l_sp_ch.value));}
	| var_symbol													{$point = std::make_unique<var_sym>(std::move($var_symbol.vs));};

l_sp_str_v returns [concat_chain chain]
	:		
	| tmp=l_sp_str_v l_sp_ch_v											{$chain = std::move($tmp.chain); $chain.push_back(std::move($l_sp_ch_v.point)); };

l_sp_string returns [std::string value]
	: 
	| tmp=l_sp_string l_sp_ch											{$value=std::move($tmp.value); $value.append(std::move($l_sp_ch.value));};

l_sp_string_v returns [concat_chain chain]
	: l_sp_string var_symbol l_sp_str_v
	{
		$chain.push_back(std::make_unique<char_str>(std::move($l_sp_string.value))); 
		$chain.push_back(std::make_unique<var_sym>(std::move($var_symbol.vs)));
		$chain.insert($chain.end(), std::make_move_iterator($l_sp_str_v.chain.begin()), std::make_move_iterator($l_sp_str_v.chain.end()));
	};


l_string_poss_space_c returns [std::string value]
	: APOSTROPHE l_sp_string APOSTROPHE										{$value.append("'"); $value.append(std::move($l_sp_string.value)); $value.append("'");}
	| tmp=l_string_poss_space_c APOSTROPHE l_sp_string APOSTROPHE			{$value=std::move($tmp.value); $value.append("'"); $value.append(std::move($l_sp_string.value)); $value.append("'");};

l_string_poss_space_c_o returns [std::string value]
	: l_string_poss_space_c													{$value = std::move($l_string_poss_space_c.value);}
	| ;

l_string_poss_space_u returns [concat_chain chain]
	: APOSTROPHE l_sp_string APOSTROPHE										
	{
		std::string tmp("'"); tmp.append(std::move($l_sp_string.value)); tmp.append("'"); 
		$chain.push_back(std::make_unique<char_str>(std::move(tmp)));
	}
	| APOSTROPHE l_sp_string_v APOSTROPHE
	{
		$chain.push_back(std::make_unique<char_str>("'"));
		$chain.insert($chain.end(), std::make_move_iterator($l_sp_string_v.chain.begin()), std::make_move_iterator($l_sp_string_v.chain.end()));
		$chain.push_back(std::make_unique<char_str>("'"));
	};

l_string_poss_space_u_c returns [concat_chain chain]
	: tmp=l_string_poss_space_u_c l_string_poss_space_u							
	{
		$chain = std::move($tmp.chain); 
		$chain.insert($chain.end(), std::make_move_iterator($l_string_poss_space_u.chain.begin()), std::make_move_iterator($l_string_poss_space_u.chain.end()));
	}
	| ;

l_string_v_apo_sp returns [concat_chain chain]
	: cl1=l_string_poss_space_c_o APOSTROPHE cl2=l_sp_string_v APOSTROPHE cl3=l_string_poss_space_u_c
	{
		$cl1.value.append("'");
		$cl2.chain.push_back(std::make_unique<char_str>("'"));
		$chain.push_back(std::make_unique<char_str>(std::move($cl1.value)));
		$chain.insert($chain.end(), std::make_move_iterator($cl2.chain.begin()), std::make_move_iterator($cl2.chain.end()));
		$chain.insert($chain.end(), std::make_move_iterator($cl3.chain.begin()), std::make_move_iterator($cl3.chain.end()));
	};





l_a_ch returns [std::string value]		//l_ch with apo
	: l_ch										{$value = std::move($l_ch.value);}
	| APOSTROPHE								{$value = "'";};


l_a_string returns [std::string value]
	: tmp=l_a_string l_a_ch							{$value = std::move($tmp.value); $value.append($l_a_ch.value);}
	| ;

l_char_string returns [std::string value]		//does not begin with apo
	: l_ch l_a_string								{$value = std::move($l_ch.value); $value.append(std::move($l_a_string.value));};

l_char_string_o returns [std::string value]
	: l_char_string									{$value = std::move($l_char_string.value);}
	| ;


l_char_string_sp returns [std::string value]
	: APOSTROPHE l_sp_string APOSTROPHE							{$value = "'"; $value.append(std::move($l_sp_string.value)); $value.append("'");}
	| tmp=l_char_string_sp APOSTROPHE l_sp_string APOSTROPHE	{$value = std::move($tmp.value); $value.append("'"); $value.append(std::move($l_sp_string.value)); $value.append("'");};

//label subrules*********************************************************





//instruction rules******************************************************

instruction returns [id_index instr]
	: ORDSYMBOL													
	{
		collector.set_instruction_field(std::move($ORDSYMBOL->getText()),symbol_range::get_range($ORDSYMBOL));
		process_instruction();
	}
	| macro_name												
	{
		collector.set_instruction_field(std::move($macro_name.value),symbol_range::get_range($macro_name.ctx));
		process_instruction();
	}
	| l_string_v			/*model*/							
	{
		collector.set_instruction_field(std::move($l_string_v.chain),symbol_range::get_range($l_string_v.ctx));
		process_instruction();
	};

//instruction rules******************************************************

//instruction subrules***************************************************

macro_name_b returns [std::string value]
	: l_ch													{$value = std::move($l_ch.value);}
	| tmp=macro_name_b l_ch									{$value = std::move($tmp.value); $value.append(std::move($l_ch.value));};

macro_name returns [std::string value]
	: ORDSYMBOL macro_name_b								{$value = std::move($ORDSYMBOL->getText()); $value.append(std::move($macro_name_b.value));};

//instruction subrules***************************************************






remark_ch: DOT|ASTERISK|MINUS|PLUS|LT|GT|COMMA|LPAR|RPAR|SLASH|EQUALS|AMPERSAND|APOSTROPHE|IDENTIFIER|VERTICAL|ORDSYMBOL|SPACE;

remark
	: remark_ch*;

remark_o returns [symbol_guard<symbol_range> range_g]
	: SPACE remark							{$range_g.value = symbol_range::get_range($remark.ctx); $range_g.valid = true;}
	|										{$range_g.valid = false;};


operands_model returns [op_rem line]													//rule for variable substitution
	: op_rem_body				{$line = std::move($op_rem_body.line);};

operands_and_remarks
	: { format.defered_operands}? SPACE defered_op_rem COMMA* (SPACE remark)?                 		//TODO make special grammar for defered, for now mac_entry
	{
		auto r = symbol_range::get_range($defered_op_rem.ctx);
		collector.set_operand_remark_field(std::move($defered_op_rem.chain),r);
	} 
	| { format.defered_operands}? SPACE COMMA* (SPACE remark)?                 		//TODO make special grammar for defered, for now mac_entry
	| {!format.defered_operands}? operands_and_remarks_nd
	|																	{collector.set_operand_remark_field(symbol_range::get_empty_range(_localctx->getStart()));};

operands_and_remarks_nd
	: { format.no_operands}? SPACE+ remark								/*noop instr*/
	{
		collector.set_operand_remark_field(std::vector<operand_ptr>(),{symbol_range::get_range($remark.ctx)});
	}
	| {!format.no_operands}? SPACE+ op_rem_body
	{
		collector.set_operand_remark_field(std::move($op_rem_body.line.operands),std::move($op_rem_body.line.remarks));
	};

defered_op_rem returns [concat_chain chain]//~(EOLLN)*; 
	: mac_entry			{$chain = std::move($mac_entry.chain);}
	| mac_entry COMMA ch=defered_op_rem
	{
		$chain = std::move($mac_entry.chain);
		$chain.push_back(std::make_unique<char_str>(","));
		$chain.insert($chain.end(), std::make_move_iterator($ch.chain.begin()), std::make_move_iterator($ch.chain.end()));
	};

op_rem_body returns [op_rem line]
	: {!format.alt_format}? op_list_comma_o operand remark_o
	{
		$op_list_comma_o.operands.push_back(std::move($operand.op));
		$line.operands = std::move($op_list_comma_o.operands);
		if($remark_o.range_g) $line.remarks.push_back($remark_o.range_g.value);
	}
	| { format.alt_format}? op_rem_body_alt
	{
		$line = std::move($op_rem_body_alt.line);
	}
	| ;

op_rem_body_alt returns [op_rem line]
	: op_list_comma_o operand_not_empty remark_o				
	{
		$op_list_comma_o.operands.push_back(std::move($operand_not_empty.op)); 
		$line.operands = std::move($op_list_comma_o.operands); 
		if($remark_o.range_g) $line.remarks.push_back($remark_o.range_g.value);
	}
	| op_list_comma cont												
	{
		$line.operands = std::move($op_list_comma.operands);
		$line.operands.insert($line.operands.end(), std::make_move_iterator($cont.line.operands.begin()), std::make_move_iterator($cont.line.operands.end()));
		$line.remarks = std::move($cont.line.remarks);
	};


cont returns [op_rem line]
	: {enable_continuation();} cont_body {disable_continuation();}						{$line = std::move($cont_body.line);};

cont_body returns [op_rem line]
	: remark_o																					
	{ 
		if($remark_o.range_g) $line.remarks.push_back($remark_o.range_g.value);
		auto tmp = std::make_unique<empty_operand>(); tmp->range = symbol_range::get_empty_range($remark_o.ctx->getStart());
		$line.operands.push_back(std::move(tmp));
	}
	| SPACE r1=remark CONTINUATION /*empty op*/ sp=SPACE {disable_continuation();} r2=remark				
	{
		$line.remarks.push_back(symbol_range::get_range($r1.ctx)); 
		auto tmp = std::make_unique<empty_operand>(); tmp->range = symbol_range::get_empty_range($sp);
		$line.operands.push_back(std::move(tmp));
		$line.remarks.push_back(symbol_range::get_range($r2.ctx));
	}
	| SPACE remark CONTINUATION {disable_continuation();} next=op_rem_body_alt
	{
		$line.remarks.push_back(symbol_range::get_range($remark.ctx));
		$line.remarks.insert($line.remarks.end(),std::make_move_iterator($next.line.remarks.begin()),std::make_move_iterator($next.line.remarks.end()));
		$line.operands = std::move($next.line.operands);
	};

op_list_comma_o returns [std::vector<operand_ptr> operands]
	: op_list_comma												{$operands = std::move($op_list_comma.operands);}
	| ;

op_list_comma returns [std::vector<operand_ptr> operands]
	: operand COMMA												{$operands.push_back(std::move($operand.op)); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($COMMA),scopes::operator_symbol)); }
	| tmp=op_list_comma operand COMMA							{$tmp.operands.push_back(std::move($operand.op)); $operands = std::move($tmp.operands); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($COMMA),scopes::operator_symbol)); };

operand returns [operand_ptr op]
	: operand_not_empty					{$op = std::move($operand_not_empty.op);}
	|									{$op = std::make_unique<empty_operand>(); $op->range = symbol_range::get_empty_range(_localctx->getStart());};


operand_not_empty returns [operand_ptr op]
	: {format.operand_type != instruction_type::CA && format.operand_type != instruction_type::MAC}? op_string_v		
	{
		$op = std::make_unique<model_operand>(std::move($op_string_v.chain)); $op->range = symbol_range::get_range($op_string_v.ctx);
	}
	| {format.operand_type == instruction_type::MACH}? mach_op																	
	{
		$op = std::make_unique<machine_operand>(std::move($mach_op.ad_op));
		$op->range = symbol_range::get_range($mach_op.ctx);
	}
	| {format.operand_type == instruction_type::ASM}? asm_op																	
	{
		$op = std::make_unique<assembler_operand>(std::move($asm_op.op));
		$op->range = symbol_range::get_range($asm_op.ctx);
	}
	| {format.operand_type == instruction_type::DAT}? data_def																	
	{
		$op = std::make_unique<empty_operand>();
		$op->range = symbol_range::get_range($data_def.ctx);
	}
	| {format.operand_type == instruction_type::CA}? ca_op																		
	{
		$op = std::move($ca_op.op); $op->range = symbol_range::get_range($ca_op.ctx);
	}
	| {format.operand_type == instruction_type::MAC}? mac_op																	
	{
		$op = std::move($mac_op.op); $op->range = symbol_range::get_range($mac_op.ctx);
	}
	| {format.operand_type == instruction_type::MACH || format.operand_type == instruction_type::ASM}? mach_expr		
	{
		
		if(format.operand_type == instruction_type::ASM)
			if($mach_expr.id_g.valid)
				$op = std::make_unique<assembler_operand>(std::make_unique<one_operand>($mach_expr.id_g.value));
			else
				$op = std::make_unique<assembler_operand>(std::make_unique<one_operand>(std::to_string($mach_expr.value)));
		else
				$op = std::make_unique<machine_operand>(std::make_unique<one_operand>(std::to_string($mach_expr.value)));
		$op->range = symbol_range::get_range($mach_expr.ctx);
	};


mach_op returns [std::unique_ptr<address_operand> ad_op]
	: disp=mach_expr_p LPAR base=mach_expr RPAR
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));

		$ad_op = std::make_unique<address_operand>(address_state::UNRES, $disp.value, $base.value, -1);
	}
	| disp=mach_expr_p LPAR index=mach_expr COMMA base=mach_expr RPAR
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($COMMA),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));

		$ad_op = std::make_unique<address_operand>(address_state::UNRES, $disp.value,$index.value, $base.value );
	}
	| disp=mach_expr_p LPAR COMMA base=mach_expr RPAR
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($COMMA),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));

		$ad_op = std::make_unique<address_operand>(address_state::UNRES, $disp.value, 0, $base.value);
	}
	;


asm_op returns [std::unique_ptr<one_operand> op]
	: string												{$op = std::make_unique<one_operand>(std::move($string.value));}	
	| id													{$op = std::make_unique<one_operand>(std::move($id.name));}
	| id LPAR asm_op_comma_c RPAR							
	{
		$op = std::make_unique<complex_operand>(std::move($id.name),std::move($asm_op_comma_c.asm_ops));
		
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));
	};

ca_op returns [operand_ptr op]
	: LPAR expr RPAR seq_symbol
	{
		$op = std::make_unique<ca_operand>(std::move($seq_symbol.ss),$expr.ctx);
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));
	}
	| seq_symbol											{$op = std::make_unique<ca_operand>(std::move($seq_symbol.ss));}
	| expr_p
	{
		if($expr_p.vs_g) 
		{
			auto tmp = std::make_unique<ca_operand>(std::move($expr_p.vs_g.value)); tmp->expression = $expr_p.ctx;
			$op = std::move(tmp);
		}
		else $op = std::make_unique<ca_operand>($expr_p.ctx);
	};

mac_op returns [operand_ptr op]
	: mac_entry												{$op = std::make_unique<macro_operand>(std::move($mac_entry.chain));};


mach_expr returns [symbol_guard<std::string> id_g, int32_t value]
	: mach_expr_p
	{
		$id_g = std::move($mach_expr_p.id_g);
		$value = $mach_expr_p.value;
	}
	| EQUALS data_def
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($EQUALS),scopes::operator_symbol));
		$id_g.valid = false;
	}
	;



mach_expr_p returns [symbol_guard<std::string> id_g, int32_t value]
	: mach_expr_s
	{
		$id_g = std::move($mach_expr_s.id_g);
		$value = $mach_expr_s.value;
	}
	| PLUS mach_expr_s
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($PLUS),scopes::operator_symbol));
		$id_g.valid = false;
		$value = $mach_expr_s.value;
	}
	| MINUS mach_expr_s
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($MINUS),scopes::operator_symbol));
		$id_g.valid = false;
		$value = - $mach_expr_s.value;
	}
	;

mach_expr_s returns [symbol_guard<std::string> id_g, int32_t value]
	: l=mach_expr_s PLUS r=mach_term_c
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($PLUS),scopes::operator_symbol));
		$id_g.valid = false;
		$value = $l.value + $r.value;
	}
	| l=mach_expr_s MINUS r=mach_term_c
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($MINUS),scopes::operator_symbol));
		$id_g.valid = false;
		$value = $l.value - $r.value;
	}
	| mach_term_c
	{
		$id_g = std::move($mach_term_c.id_g);
		$value = $mach_term_c.value;
	}
	;

mach_term_c returns [symbol_guard<std::string> id_g, int32_t value]
	: mach_term
	{
		$id_g = std::move($mach_term.id_g);
		$value = $mach_term.value;
	}
	| l=mach_term_c SLASH r=mach_term 
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($SLASH),scopes::operator_symbol));
		$id_g.valid = false;
		$value = $r.value==0 ? 0 : $l.value / $r.value;
	}
	| l=mach_term_c ASTERISK r=mach_term
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($ASTERISK),scopes::operator_symbol));
		$id_g.valid = false;
		$value = $l.value * $r.value;
	}
	;

mach_term returns [symbol_guard<std::string> id_g, int32_t value]
	: LPAR mach_expr RPAR
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));
		$id_g = std::move($mach_expr.id_g);
		$value = $mach_expr.value;
	}
	| ASTERISK			 { $value = 0; }
	| {!is_self_def()}? data_attribute { $value =0; /*analyzer.evaluate_expression_tree($data_attribute.ctx)->get_numeric_value();*/ }
	| id
	{
		size_t conv = 0;
		try
		{
			$value = std::stoi($id.name, &conv);
		}
		catch(std::invalid_argument)
		{}
		catch(std::out_of_range)
		{}
		
		$id_g = symbol_guard<std::string>(std::move($id.name));
	}
	| { is_self_def()}? o=ORDSYMBOL string
	{
		auto ae = arithmetic_expression::from_string($o.text, $string.value, false); //could generate diagnostic + DBCS
		$value = ae->get_numeric_value();
	};

expr // returns [expr_ptr e]
	: SPACE expr_p_space_c
	| expr_p_space_c									
	;

expr_p returns [symbol_guard<var_sym> vs_g]
	: expr_s
	{
		$vs_g = std::move($expr_s.vs_g);
	}
	| PLUS expr_p
	{
		$vs_g.valid = false;
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($PLUS),scopes::operator_symbol));
	}
	| MINUS expr_p
	{
		$vs_g.valid = false;
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($MINUS),scopes::operator_symbol));
	};

expr_s returns [symbol_guard<var_sym> vs_g]
	: tmp=expr_s PLUS term_c							
	{
		$vs_g.valid = false;
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($PLUS),scopes::operator_symbol));
	}
	| tmp=expr_s MINUS term_c							
	{
		$vs_g.valid = false;
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($MINUS),scopes::operator_symbol));
	}
	| t=term_c											{$vs_g = std::move($term_c.vs_g);};

term_c returns [symbol_guard<var_sym> vs_g]
	: t=term												
	{
		$vs_g = std::move($term.vs_g);
	}
	| tmp=term_c SLASH term								
	{
		$vs_g.valid = false;
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($SLASH),scopes::operator_symbol));
	}
	| tmp=term_c ASTERISK term							
	{
		$vs_g.valid = false;
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($ASTERISK),scopes::operator_symbol));
	};

term returns [symbol_guard<var_sym> vs_g]
	: LPAR expr RPAR									
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));
	}
	| var_symbol
	{
		$vs_g.value = $var_symbol.vs; //***no need for copy, however expression visitor change would be reqired
		$vs_g.valid = true;
	}
	| ca_string											{ semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($ca_string.ctx),scopes::string));}
	| {!is_self_def()}? data_attribute
	| { is_self_def()}? ORDSYMBOL string
	| id subscript										
	{ 
		$vs_g.value = var_sym($id.name,std::move($subscript.exprs_g.value),symbol_range::get_range($id.ctx->getStart(),$subscript.ctx->getStop())); 
		$vs_g.valid = true;
	};

expr_p_comma_c returns [std::vector<ParserRuleContext*> ext]
	: expr_p
	{ 
		$ext.push_back($expr_p.ctx); 
	}
	| exs=expr_p_comma_c COMMA expr_p
	{ 
		$exs.ext.push_back($expr_p.ctx); 
		$ext = $exs.ext;
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($COMMA),scopes::operator_symbol));
	}
	;
	
expr_p_space_c
	: expr_p
	| exs=expr_p_space_c SPACE expr_p
	;


id_ch returns [std::string value]
	: IDENTIFIER								{$value = std::move($IDENTIFIER->getText());} 
	| ORDSYMBOL									{$value = std::move($ORDSYMBOL->getText());};

id_ch_c returns [std::string value]
	: id_ch										{$value = std::move($id_ch.value);}
	| tmp=id_ch_c id_ch							{$tmp.value.append(std::move($id_ch.value));  $value = std::move($tmp.value);};


id returns [std::string name, std::string using_qualifier]
	: id_no_dot									{$name = std::move($id_no_dot.value);}
	| id_no_dot DOT id_no_dot					{$name = std::move($id_no_dot.value); $using_qualifier = std::move($id_no_dot.value); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($DOT),scopes::operator_symbol));};

id_no_dot returns [std::string value]
	: id_ch_c									{$value = std::move($id_ch_c.value);};


opt_dot returns [std::string value]
	: DOT id_ch_c								{$value = std::move($id_ch_c.value); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($DOT),scopes::operator_symbol));}
	| ;

id_comma_c: id
	|  id COMMA id_comma_c {semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($COMMA),scopes::operator_symbol));}
	;

asm_op_comma_c returns [std::vector<std::unique_ptr<one_operand>> asm_ops]
	: asm_op															{$asm_ops.push_back(std::move($asm_op.op));}
	|  tmp=asm_op_comma_c COMMA asm_op									{$tmp.asm_ops.push_back(std::move($asm_op.op)); $asm_ops = std::move($tmp.asm_ops);};	


op_ch returns [std::string value]
	: common_ch								{$value = std::move($common_ch.value);}
	| LPAR									{$value = "("; semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));}
	| RPAR									{$value = ")"; semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));};

op_ch_c returns [std::string value]
	:
	| tmp=op_ch_c op_ch							{$value = std::move($tmp.value); $value.append($op_ch.value);};

op_ch_v returns [concat_point_ptr point]
	: common_ch_v							{$point = std::move($common_ch_v.point);}
	| EQUALS								{$point = std::make_unique<char_str>("=");}
	| LPAR									{$point = std::make_unique<char_str>("("); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));}
	| RPAR									{$point = std::make_unique<char_str>(")"); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));};

op_ch_v_c returns [concat_chain chain]
	:
	| tmp=op_ch_v_c op_ch_v						{$tmp.chain.push_back(std::move($op_ch_v.point)); $chain = std::move($tmp.chain);};

op_string_v returns [concat_chain chain]
	: op_string_v_p								{$chain = std::move($op_string_v_p.chain);}
	| APOSTROPHE op_string_v_p APOSTROPHE
	{
		$chain.push_back(std::make_unique<char_str>("'"));
		$chain.insert($chain.end(), std::make_move_iterator($op_string_v_p.chain.begin()), std::make_move_iterator($op_string_v_p.chain.end()));
		$chain.push_back(std::make_unique<char_str>("'"));
	};

op_string_v_p returns [concat_chain chain]
	: op_ch_c var_symbol cl=op_ch_v_c
	{
		$chain.push_back(std::make_unique<char_str>(std::move($op_ch_c.value)));
		$chain.push_back(std::make_unique<var_sym>(std::move($var_symbol.vs)));
		$chain.insert($chain.end(), 
			std::make_move_iterator($op_ch_v_c.chain.begin()), 
			std::make_move_iterator($op_ch_v_c.chain.end())
		);
	};


data_attribute // returns [expr_ptr e]
	: ORDSYMBOL APOSTROPHE EQUALS data_def				{semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($EQUALS),scopes::operator_symbol)); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($APOSTROPHE),scopes::operator_symbol));}
	| ORDSYMBOL APOSTROPHE string						{semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($APOSTROPHE),scopes::operator_symbol));}
	| ORDSYMBOL APOSTROPHE var_symbol					{semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($APOSTROPHE),scopes::operator_symbol));}
	| ORDSYMBOL APOSTROPHE id							{semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($APOSTROPHE),scopes::operator_symbol));}
	;

seq_symbol returns [seq_sym ss]
	: DOT id									
	{	
		auto current_seq_occurence = create_occurence(symbol_range::get_range($DOT,$id.ctx->getStop()), $id.name);
		semantic_info.seq_symbols.push_back(current_seq_occurence,is_seq_definition(current_seq_occurence));
		$ss.name = std::move($id.name); $ss.location = statement_start();
		$ss.range = symbol_range::get_range($DOT,$id.ctx->getStop());
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($DOT,$id.ctx->getStop()),scopes::seq_symbol)); 
	};



subscript returns [symbol_guard<std::vector<ParserRuleContext*>> exprs_g]
	: LPAR expr_p_comma_c RPAR
	{
		$exprs_g.valid=true; 
		$exprs_g.value = $expr_p_comma_c.ext;
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));
	}
	|														{$exprs_g.valid=false;};



created_set_body returns [concat_point_ptr point]
	: ORDSYMBOL												{$point = std::make_unique<char_str>(std::move($ORDSYMBOL->getText()));}
	| IDENTIFIER											{$point = std::make_unique<char_str>(std::move($IDENTIFIER->getText()));}
	| var_symbol											{$point = std::make_unique<var_sym>(std::move($var_symbol.vs));}
	| DOT													{$point = std::make_unique<dot>(); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($DOT),scopes::operator_symbol));};

created_set_body_c returns [concat_chain concat_list]
	: cl=created_set_body													{$concat_list.push_back(std::move($cl.point));}
	| clc=created_set_body_c cl=created_set_body							{$clc.concat_list.push_back(std::move($cl.point)); $concat_list =std::move($clc.concat_list);};

created_set_symbol returns [var_sym vs]
	: AMPERSAND LPAR clc=created_set_body_c RPAR subscript 	
	{
		$vs = var_sym(std::move($clc.concat_list),std::move($subscript.exprs_g.value),symbol_range::get_range($AMPERSAND,$subscript.ctx->getStop()));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($AMPERSAND),scopes::operator_symbol));
	}
	| AMPERSAND LPAR RPAR subscript; 	//empty set symbol err;			

var_symbol returns [var_sym vs]
	: AMPERSAND id_no_dot tmp=subscript								{
																		auto id = std::move($id_no_dot.value); 
																		auto r = symbol_range::get_range($AMPERSAND,$tmp.ctx->getStop()); 
																		$vs = var_sym(id, std::move($tmp.exprs_g.value), r);
																		auto var_symbol_occurence = create_occurence(r, $vs.name,true);
																		semantic_info.var_symbols.push_back(var_symbol_occurence,false);
																		semantic_info.hl_info.lines.push_back(token_info(r,scopes::var_symbol));
																	}
	| created_set_symbol 											{$vs = std::move($created_set_symbol.vs);};




dupl_factor: LPAR mach_expr RPAR {semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol)); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));}			//absolute
	|;

modifer: id_no_dot
	   | ;

prog_type_and_modifier: LPAR  ORDSYMBOL string RPAR modifer	{semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol)); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));}	// self def term - dec/char/hex/bin ORDSYMBOL + modifier
		| LPAR id_no_dot RPAR modifer {semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol)); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));};									// symbol + modifier

nominal_value: string 
	| LPAR mach_expr_comma_c RPAR {semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol)); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));};

nominal_value_o: nominal_value
	|;

mach_expr_comma_c: mach_expr
	| mach_expr_comma_c COMMA mach_expr {semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($COMMA),scopes::operator_symbol));};


data_def: 
	dupl_factor id_no_dot prog_type_and_modifier nominal_value
	| dupl_factor id_no_dot nominal_value_o;




mac_str_ch returns [concat_point_ptr point]
	: common_ch_v									{$point = std::move($common_ch_v.point);}
	| EQUALS										{$point = std::make_unique<char_str>("=");}
	| SPACE											{$point = std::make_unique<char_str>(" ");};

mac_str_b returns [concat_chain chain]
	:
	| tmp=mac_str_b mac_str_ch						{$tmp.chain.push_back(std::move($mac_str_ch.point)); $chain = std::move($tmp.chain);};

mac_str returns [concat_chain chain]
	: ap1=APOSTROPHE mac_str_b ap2=APOSTROPHE				
	{
		$chain.push_back(std::make_unique<char_str>("'"));
		$chain.insert($chain.end(), std::make_move_iterator($mac_str_b.chain.begin()), std::make_move_iterator($mac_str_b.chain.end()));
		$chain.push_back(std::make_unique<char_str>("'"));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($ap1,$ap2),scopes::string));
	};

mac_ch returns [concat_chain chain]
	: common_ch_v									{$chain.push_back(std::move($common_ch_v.point));}
	| EQUALS										{$chain.push_back(std::make_unique<equals>());}
	| mac_str										{$chain = std::move($mac_str.chain);}
	| mac_sublist									{$chain.push_back(std::move($mac_sublist.point));};

mac_ch_c returns [concat_chain chain]
	:
	| tmp=mac_ch_c mac_ch							
	{
		$chain = std::move($tmp.chain);
		$chain.insert($chain.end(), std::make_move_iterator($mac_ch.chain.begin()), std::make_move_iterator($mac_ch.chain.end()));
	};

mac_entry returns [concat_chain chain]
	: mac_ch										{$chain = std::move($mac_ch.chain);}
	| tmp=mac_entry mac_ch							
	{
		$chain = std::move($tmp.chain);
		$chain.insert($chain.end(), std::make_move_iterator($mac_ch.chain.begin()), std::make_move_iterator($mac_ch.chain.end()));
	};

mac_sublist_b returns [concat_chain chain]
	: mac_ch_c										{$chain = std::move($mac_ch_c.chain);}
	| tmp=mac_sublist_b COMMA mac_ch_c			
	{
		$chain = std::move($tmp.chain);
		$chain.insert($chain.end(), std::make_move_iterator($mac_ch_c.chain.begin()), std::make_move_iterator($mac_ch_c.chain.end()));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($COMMA),scopes::operator_symbol));
	};

mac_sublist returns [concat_point_ptr point]
	: LPAR mac_sublist_b RPAR						{$point = std::make_unique<sublist>(std::move($mac_sublist_b.chain)); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol)); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));};


//not adn not and

string_ch returns [std::string value]
	: l_sp_ch							{$value = std::move($l_sp_ch.value);}
	| APOSTROPHE APOSTROPHE				{$value = "'";};

string_ch_c returns [std::string value]
	:
	| tmp=string_ch_c string_ch				{$value = std::move($tmp.value); $value.append($string_ch.value);};

string_ch_v returns [concat_point_ptr point]
	: l_sp_ch_v							{$point = std::move($l_sp_ch_v.point);}
	| APOSTROPHE APOSTROPHE				{$point = std::make_unique<char_str>("'");};

string_ch_v_c returns [concat_chain chain]
	:
	| cl=string_ch_v_c string_ch_v		{$cl.chain.push_back(std::move($string_ch_v.point)); $chain = std::move($cl.chain);};



string returns [std::string value]
	: ap1=APOSTROPHE string_ch_c ap2=APOSTROPHE					{ $value.append("'"); $value.append(std::move($string_ch_c.value)); $value.append("'"); semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($ap1,$ap2),scopes::string)); };


ca_dupl_factor // returns [int32_t df]
	: LPAR expr_p RPAR															
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));
	}
	|;

substring // returns [expr_ptr start, expr_ptr end]
	: LPAR e1=expr_p COMMA e2=expr_p RPAR
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($COMMA),scopes::operator_symbol));
	}
	| LPAR expr_p COMMA ASTERISK RPAR
	{
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($COMMA),scopes::operator_symbol));
	}
	| LPAR expr_p RPAR
	{
		
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($LPAR),scopes::operator_symbol));
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($RPAR),scopes::operator_symbol));
	}
	| ;

ca_string_b // returns [std::unique_ptr<char_expr> e]
	: ca_dupl_factor ap1=APOSTROPHE string_ch_v_c ap2=APOSTROPHE substring
	{ 
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($ap1),scopes::operator_symbol)); 
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($ap2),scopes::operator_symbol));
	};

ca_string // returns [std::unique_ptr<char_expr> e]
	: ca_string_b											//	{$e = std::move($ca_string_b.e);}
	| tmp=ca_string DOT ca_string_b
	{
		
		semantic_info.hl_info.lines.push_back(token_info(symbol_range::get_range($DOT),scopes::operator_symbol));
	};








expr_statement
	: expr
	| tmp=expr_statement EOLLN expr
	;

expr_test
	:  expr_statement EOLLN EOF	;