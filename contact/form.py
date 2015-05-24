from django import forms
from .models import Article

class ContactForm(forms.ModelForm):
	class Meta:
		model = Article
		fields=('sujet','message','auteur',)