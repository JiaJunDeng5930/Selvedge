import Base
import ./form-input-laws.bend as Rule

def Rule.evidence():
  Rule.Requirements{
    id => revision => draft => assist => profile => keep_open => {==},
    editor => value => +text => state => {==},
    values => title => description => stage => priority => owner => project => previous => attachments => {==},
    values => {==},
    choices => key => editor => values => label => role => context => {==},
    values => {==},
    choices => key => editor => enabled => profile => label => role => context => {==},
    choices => key => editor => enabled => profile => label => role => context => {==},
    choices => key => semantic => label => role => editor => previous => profile => children => enabled => {==},
    enabled => selected => previous => profile => {==},
    enabled => selected => previous => profile => {==},
    stage => rest => {==},
    priority => rest => {==},
    value => {==},
    value => {==}}
