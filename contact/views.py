from contact.form import ContactForm
from django.shortcuts import render,redirect

def contact(request):
	if request.method == 'POST':
		form = ContactForm(request.POST)
		if form.is_valid(): 
			form.save()
			return redirect('contact.views.merci')
	else:
		form = ContactForm()
	return render(request, 'contact/contact.html', locals())

def merci(request):
	return render(request, 'contact/merci.html', locals())