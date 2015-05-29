from contact.form import ContactForm
from django.shortcuts import render

def contact(request):
	if request.method == 'POST':
		form = ContactForm(request.POST)
		if form.is_valid(): 
			form.save()
	else:
		form = ContactForm()
	return render(request, 'contact/contact.html', locals())
	