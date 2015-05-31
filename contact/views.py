from contact.form import ContactForm
from django.shortcuts import render,redirect
from vote.views import hasard

def contact(request):
	if request.method == 'POST':
		form = ContactForm(request.POST)
		if form.is_valid(): 
			form.save()
			return redirect('contact.views.merci')
	else:
		form = ContactForm()
		cita=hasard()
	return render(request, 'contact/contact.html', {'form': form,'cita':cita})

def merci(request):
	cita=hasard()
	return render(request, 'contact/merci.html', {'cita':cita})