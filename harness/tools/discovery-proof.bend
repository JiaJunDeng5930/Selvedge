import Base
import ./discovery.bend as Discovery

def Discovery.definition_name():
  name => description => parameters => source => {==}
def Discovery.definition_parameters():
  name => description => parameters => source => {==}
def Discovery.exact_ignores_keywords():
  terms => names => name => description => {==}
def Discovery.exact_ignores_page():
  matches => offset => limit => {==}
def Discovery.native_not_deferred():
  program => {==}
def Discovery.resident_parameters():
  tool => {==}
def Discovery.deferred_parameters_independent():
  tool => {==}
def Discovery.presentation_name():
  available => tool => {==}
def Discovery.unavailable_preserves_parameters():
  tool => {==}
