from django import forms
from .models import voteForm

class vote_Form(forms.ModelForm):
	class Meta:
		model = voteForm
		fields=('formDep','formVote',)